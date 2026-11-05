-- ТРИГГЕР 1 (BEFORE INSERT/UPDATE, строка): проверка строки продажи.
-- Позиции можно менять только в черновике, и товара должно хватать на складе.
CREATE OR REPLACE FUNCTION tg_items_check()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_status varchar;
    v_stock  integer;
BEGIN
    SELECT sale_status INTO v_status FROM sales WHERE sale_id = NEW.item_sale_id;
    IF v_status IS NOT NULL AND v_status <> 'draft' THEN
        RAISE EXCEPTION 'Нельзя менять позиции: продажа % уже в статусе %', NEW.item_sale_id, v_status;
    END IF;

    SELECT med_stock INTO v_stock FROM medicines WHERE med_id = NEW.item_med_id;
    IF v_stock IS NOT NULL AND v_stock < NEW.item_qty THEN
        RAISE EXCEPTION 'Недостаточно на складе: нужно %, есть %', NEW.item_qty, v_stock;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_items_check ON sale_items;
CREATE TRIGGER trg_items_check
    BEFORE INSERT OR UPDATE ON sale_items
    FOR EACH ROW EXECUTE FUNCTION tg_items_check();

-- ТРИГГЕР 2 (AFTER INSERT/UPDATE/DELETE, строка): автоматический пересчёт суммы продажи.
CREATE OR REPLACE FUNCTION tg_items_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_sale integer;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_sale := OLD.item_sale_id;
    ELSE
        v_sale := NEW.item_sale_id;
    END IF;

    UPDATE sales SET sale_total = fn_sale_total(v_sale) WHERE sale_id = v_sale;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_items_total ON sale_items;
CREATE TRIGGER trg_items_total
    AFTER INSERT OR UPDATE OR DELETE ON sale_items
    FOR EACH ROW EXECUTE FUNCTION tg_items_total();

-- ТРИГГЕР 3 (BEFORE UPDATE OF sale_status): порядок статусов и запрет пустой продажи.
CREATE OR REPLACE FUNCTION tg_sales_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.sale_status = OLD.sale_status THEN
        RETURN NEW;
    END IF;

    IF NOT ((OLD.sale_status = 'draft'     AND NEW.sale_status = 'confirmed') OR
            (OLD.sale_status = 'confirmed' AND NEW.sale_status = 'closed')) THEN
        RAISE EXCEPTION 'Недопустимый переход статуса: % -> %', OLD.sale_status, NEW.sale_status;
    END IF;

    IF NEW.sale_status = 'confirmed'
       AND NOT EXISTS (SELECT 1 FROM sale_items WHERE item_sale_id = NEW.sale_id) THEN
        RAISE EXCEPTION 'Нельзя подтвердить продажу % без позиций', NEW.sale_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_status ON sales;
CREATE TRIGGER trg_sales_status
    BEFORE UPDATE OF sale_status ON sales
    FOR EACH ROW EXECUTE FUNCTION tg_sales_status();

-- ТРИГГЕР 4 (BEFORE DELETE): подтверждённые и закрытые продажи удалять нельзя.
CREATE OR REPLACE FUNCTION tg_sales_no_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.sale_status <> 'draft' THEN
        RAISE EXCEPTION 'Нельзя удалить продажу % в статусе %', OLD.sale_id, OLD.sale_status;
    END IF;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_sales_no_delete ON sales;
CREATE TRIGGER trg_sales_no_delete
    BEFORE DELETE ON sales
    FOR EACH ROW EXECUTE FUNCTION tg_sales_no_delete();

-- ТРИГГЕР 5 (аудит, AFTER, строка): пишем старое и новое значение в audit_log.
-- Одна функция на несколько таблиц: имя таблицы берём из TG_TABLE_NAME, операцию из TG_OP.
CREATE OR REPLACE FUNCTION tg_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (log_table, log_op, log_new) VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(NEW));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (log_table, log_op, log_old, log_new) VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
    ELSE
        INSERT INTO audit_log (log_table, log_op, log_old) VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD));
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_medicines ON medicines;
CREATE TRIGGER trg_audit_medicines
    AFTER INSERT OR UPDATE OR DELETE ON medicines
    FOR EACH ROW EXECUTE FUNCTION tg_audit();

DROP TRIGGER IF EXISTS trg_audit_customers ON customers;
CREATE TRIGGER trg_audit_customers
    AFTER INSERT OR UPDATE OR DELETE ON customers
    FOR EACH ROW EXECUTE FUNCTION tg_audit();

-- ТРИГГЕР 6 (уровень оператора, FOR EACH STATEMENT): срабатывает один раз на весь DELETE.
CREATE OR REPLACE FUNCTION tg_medicines_stmt()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE NOTICE 'Выполнено удаление из medicines (оператор целиком)';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_medicines_stmt ON medicines;
CREATE TRIGGER trg_medicines_stmt
    AFTER DELETE ON medicines
    FOR EACH STATEMENT EXECUTE FUNCTION tg_medicines_stmt();

-- Список триггеров базы:
SELECT event_object_table AS table_name, trigger_name, event_manipulation, action_timing
FROM   information_schema.triggers
ORDER  BY 1, 2;
