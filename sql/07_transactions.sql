-- ПРИМЕР 1. COMMIT и SAVEPOINT.
-- Запускайте по шагам в ОДНОЙ вкладке Query Tool: выделили кусок - F5.
BEGIN;

INSERT INTO customers (cust_name, cust_phone) VALUES ('Тест Первый', '+7 000 000 00 01');

SAVEPOINT sp1;

INSERT INTO customers (cust_name, cust_phone) VALUES ('Тест Второй', '+7 000 000 00 02');

SELECT cust_id, cust_name FROM customers ORDER BY cust_id;   -- видны оба

ROLLBACK TO sp1;                                              -- второй отменён

SELECT cust_id, cust_name FROM customers ORDER BY cust_id;   -- остался только первый

COMMIT;

-- Уборка после примера:
DELETE FROM customers WHERE cust_phone IN ('+7 000 000 00 01', '+7 000 000 00 02');

-- ПРИМЕР 2. Полный ROLLBACK: ничего не сохраняется.
BEGIN;

UPDATE medicines SET med_stock = med_stock - 5 WHERE med_id = 1;
SELECT med_name, med_stock FROM medicines WHERE med_id = 1;   -- на 5 меньше

ROLLBACK;

SELECT med_name, med_stock FROM medicines WHERE med_id = 1;   -- как было

-- ПРИМЕР 3. Ошибка внутри транзакции: PostgreSQL помечает её как «сломанную».
BEGIN;
UPDATE medicines SET med_stock = med_stock - 1000 WHERE med_id = 1;  -- ошибка CHECK (med_stock >= 0)
SELECT 1;                                                              -- ошибка: транзакция прервана
ROLLBACK;

-- ПРИМЕР 4. Оформление заказа одной транзакцией (то же делает API, см. /api/orders/checkout).
-- Нужен скрипт 06 и 09. Заказ из двух позиций, вторая не проходит -> откатывается ВСЁ.
BEGIN;

SELECT fn_create_sale(2);                     -- запомните номер, например 7
CALL sp_add_item(7, 1, 2);                    -- хватает
CALL sp_add_item(7, 10, 1);                   -- Цитрамон: остаток 0 -> ошибка
ROLLBACK;

SELECT * FROM sales ORDER BY sale_id DESC LIMIT 3;  -- новой продажи нет

-- ПРИМЕР 5. Уровни изоляции. Нужны ДВЕ вкладки Query Tool (сеанс A и сеанс B).
-- Сеанс A:
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT med_stock FROM medicines WHERE med_id = 1;      -- например 100

-- Сеанс B (отдельная вкладка), выполнить целиком:
-- UPDATE medicines SET med_stock = 77 WHERE med_id = 1;   (автофиксация, COMMIT не нужен)

-- Сеанс A, снова:
SELECT med_stock FROM medicines WHERE med_id = 1;      -- 77: изменение видно (неповторяемое чтение)
COMMIT;

-- Теперь то же на REPEATABLE READ. Сеанс A:
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT med_stock FROM medicines WHERE med_id = 1;      -- 77

-- Сеанс B:
-- UPDATE medicines SET med_stock = 55 WHERE med_id = 1;

-- Сеанс A:
SELECT med_stock FROM medicines WHERE med_id = 1;      -- всё ещё 77: у транзакции свой снимок
COMMIT;
SELECT med_stock FROM medicines WHERE med_id = 1;      -- после COMMIT видно 55

-- Вернуть исходное значение:
UPDATE medicines SET med_stock = 100 WHERE med_id = 1;
