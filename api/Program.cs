using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Строка подключения лежит в appsettings.json, а не в коде.
var connectionString = builder.Configuration.GetConnectionString("Pharmacy")
    ?? throw new InvalidOperationException("Нет строки подключения Pharmacy в appsettings.json");
builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));

var app = builder.Build();
app.UseSwagger();
app.UseSwaggerUI();
app.UseDefaultFiles();   // отдаёт wwwroot/index.html по адресу /
app.UseStaticFiles();

// ---------- Справочники и поиск (SELECT из представления) ----------

app.MapGet("/api/medicines", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT med_id, med_name, med_price, med_stock, cat_name, stock_value, med_tags FROM v_medicines_full ORDER BY med_id"))));

// Поиск с параметром @q (никакой склейки строк - защита от SQL-инъекций).
app.MapGet("/api/medicines/search", (string q, NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT med_id, med_name, med_price, med_stock FROM medicines WHERE med_name ILIKE '%' || @q || '%' ORDER BY med_name",
        new NpgsqlParameter("q", q)))));

// Лекарства с тегом (массив) и по полю jsonb.
app.MapGet("/api/medicines/by-tag/{tag}", (string tag, NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT med_id, med_name, med_tags FROM medicines WHERE @tag = ANY (med_tags) ORDER BY med_id",
        new NpgsqlParameter("tag", tag)))));

app.MapGet("/api/medicines/prescription", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT med_id, med_name, med_info::text AS med_info FROM medicines WHERE med_info @> '{\"рецепт\": true}'::jsonb ORDER BY med_id"))));

app.MapGet("/api/customers", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT cust_id, cust_name, cust_phone, cust_discount FROM customers ORDER BY cust_id"))));

app.MapPost("/api/customers", (CustomerDto dto, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    var rows = await Db.QueryAsync(ds,
        "INSERT INTO customers (cust_name, cust_phone) VALUES (@n, @p) RETURNING cust_id, cust_name, cust_phone",
        new NpgsqlParameter("n", dto.Name), new NpgsqlParameter("p", (object?)dto.Phone ?? DBNull.Value));
    return Results.Created($"/api/customers/{rows[0]["cust_id"]}", rows[0]);
}));

app.MapPut("/api/medicines/{id:int}/price", (int id, PriceDto dto, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    var n = await Db.ExecAsync(ds, "UPDATE medicines SET med_price = @p WHERE med_id = @id",
        new NpgsqlParameter("p", dto.Price), new NpgsqlParameter("id", id));
    return n == 0 ? Results.NotFound(new { error = "Лекарство не найдено" }) : Results.Ok(new { updated = n });
}));

// ---------- Продажи: цепочка «клиент -> продажа -> позиции -> подтверждение» ----------

app.MapGet("/api/sales", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds, "SELECT * FROM v_sales_full ORDER BY sale_id DESC"))));

// Создать продажу-черновик: вызываем функцию БД.
app.MapPost("/api/sales", (CreateSaleDto dto, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await using var cmd = ds.CreateCommand("SELECT fn_create_sale(@c)");
    cmd.Parameters.AddWithValue("c", dto.CustomerId);
    var id = (int)(await cmd.ExecuteScalarAsync())!;
    return Results.Created($"/api/sales/{id}", new { sale_id = id });
}));

// Добавить позицию: вызываем процедуру. Все проверки (статус, остаток) делают триггеры в БД.
app.MapPost("/api/sales/{id:int}/items", (int id, ItemDto dto, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await Db.ExecAsync(ds, "CALL sp_add_item(@s, @m, @q)",
        new NpgsqlParameter("s", id), new NpgsqlParameter("m", dto.MedicineId), new NpgsqlParameter("q", dto.Qty));
    return Results.Ok(new { ok = true });
}));

app.MapGet("/api/sales/{id:int}/items", (int id, NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT i.item_id, m.med_name, i.item_qty, i.item_price FROM sale_items i JOIN medicines m ON m.med_id = i.item_med_id WHERE i.item_sale_id = @id ORDER BY i.item_id",
        new NpgsqlParameter("id", id)))));

// Подтверждение в явной транзакции C# (NpgsqlTransaction).
app.MapPost("/api/sales/{id:int}/confirm", (int id, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await using var conn = await ds.OpenConnectionAsync();
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        await using var cmd = new NpgsqlCommand("CALL sp_confirm_sale(@id)", conn, tx);
        cmd.Parameters.AddWithValue("id", id);
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
    }
    catch
    {
        await tx.RollbackAsync();
        throw;
    }
    return Results.Ok(new { ok = true });
}));

app.MapDelete("/api/sales/{id:int}", (int id, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await Db.ExecAsync(ds, "CALL sp_delete_draft(@id)", new NpgsqlParameter("id", id));
    return Results.NoContent();
}));

// ГЛАВНАЯ ТРАНЗАКЦИЯ: весь заказ целиком. Любая ошибка на любом шаге -> ROLLBACK, в базе ничего нет.
app.MapPost("/api/orders/checkout", (CheckoutDto dto, NpgsqlDataSource ds) => Db.Safe(async () =>
{
    if (dto.Items is null || dto.Items.Count == 0)
        return Results.BadRequest(new { error = "В заказе нет позиций" });

    await using var conn = await ds.OpenConnectionAsync();
    await using var tx = await conn.BeginTransactionAsync();
    try
    {
        int saleId;
        await using (var create = new NpgsqlCommand("SELECT fn_create_sale(@c)", conn, tx))
        {
            create.Parameters.AddWithValue("c", dto.CustomerId);
            saleId = (int)(await create.ExecuteScalarAsync())!;
        }

        foreach (var item in dto.Items)
        {
            await using var add = new NpgsqlCommand("CALL sp_add_item(@s, @m, @q)", conn, tx);
            add.Parameters.AddWithValue("s", saleId);
            add.Parameters.AddWithValue("m", item.MedicineId);
            add.Parameters.AddWithValue("q", item.Qty);
            await add.ExecuteNonQueryAsync();
        }

        await using (var confirm = new NpgsqlCommand("CALL sp_confirm_sale(@s)", conn, tx))
        {
            confirm.Parameters.AddWithValue("s", saleId);
            await confirm.ExecuteNonQueryAsync();
        }

        await tx.CommitAsync();
        return Results.Created($"/api/sales/{saleId}", new { sale_id = saleId });
    }
    catch
    {
        await tx.RollbackAsync();
        throw;
    }
}));

// ---------- Отчёты ----------

app.MapGet("/api/reports/revenue", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds, "SELECT cat_id, cat_name, revenue FROM mv_revenue_by_category ORDER BY cat_id"))));

// Кнопка «Обновить отчёт» на сайте вызывает именно этот endpoint.
app.MapPost("/api/reports/refresh", (NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await Db.ExecAsync(ds, "REFRESH MATERIALIZED VIEW mv_revenue_by_category");
    return Results.Ok(new { refreshed = true });
}));

app.MapGet("/api/reports/top-medicines", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds, "SELECT * FROM fn_top_medicines(5)"))));

// Курсорная функция БД.
app.MapPost("/api/discounts/recalculate", (NpgsqlDataSource ds) => Db.Safe(async () =>
{
    await using var cmd = ds.CreateCommand("SELECT fn_update_discounts()");
    var changed = (int)(await cmd.ExecuteScalarAsync())!;
    return Results.Ok(new { changed });
}));

app.MapGet("/api/audit", (NpgsqlDataSource ds) => Db.Safe(async () =>
    Results.Ok(await Db.QueryAsync(ds,
        "SELECT log_id, log_time, log_table, log_op, log_old::text AS log_old, log_new::text AS log_new FROM audit_log ORDER BY log_id DESC LIMIT 50"))));

app.Run();

// ---------- DTO ----------
record CustomerDto(string Name, string? Phone);
record PriceDto(decimal Price);
record CreateSaleDto(int CustomerId);
record ItemDto(int MedicineId, int Qty);
record CheckoutDto(int CustomerId, List<ItemDto> Items);

// ---------- Работа с БД ----------
static class Db
{
    public static async Task<List<Dictionary<string, object?>>> QueryAsync(
        NpgsqlDataSource ds, string sql, params NpgsqlParameter[] ps)
    {
        await using var cmd = ds.CreateCommand(sql);
        cmd.Parameters.AddRange(ps);
        await using var reader = await cmd.ExecuteReaderAsync();
        var rows = new List<Dictionary<string, object?>>();
        while (await reader.ReadAsync())
        {
            var row = new Dictionary<string, object?>();
            for (int i = 0; i < reader.FieldCount; i++)
                row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            rows.Add(row);
        }
        return rows;
    }

    public static async Task<int> ExecAsync(NpgsqlDataSource ds, string sql, params NpgsqlParameter[] ps)
    {
        await using var cmd = ds.CreateCommand(sql);
        cmd.Parameters.AddRange(ps);
        return await cmd.ExecuteNonQueryAsync();
    }

    // Превращает ошибки PostgreSQL в понятный JSON и нужный HTTP-код (а не просто 500).
    public static async Task<IResult> Safe(Func<Task<IResult>> action)
    {
        try
        {
            return await action();
        }
        catch (PostgresException ex)
        {
            var status = ex.SqlState switch
            {
                "P0001" => 400,   // наш RAISE EXCEPTION из процедур и триггеров
                "23514" => 400,   // нарушен CHECK
                "23502" => 400,   // NOT NULL
                "23505" => 409,   // дубликат UNIQUE
                "23503" => 409,   // нарушен внешний ключ
                _ => 500
            };
            return Results.Json(new { error = ex.MessageText, sqlState = ex.SqlState }, statusCode: status);
        }
    }
}
