-- СЦЕНАРИИ ДЛЯ ЗАЩИТЫ. Запускать после скриптов 01-09. Каждый блок выполняйте отдельно.

-- Сценарий 1. Порядок заполнения: нельзя добавить позицию в подтверждённую продажу.
CALL sp_add_item(2, 1, 1);
-- ожидаем: ERROR: Нельзя менять позиции: продажа 2 уже в статусе confirmed

-- Нельзя подтвердить пустую продажу.
SELECT fn_create_sale(5);            -- получили номер новой продажи, например 7
CALL sp_confirm_sale(7);             -- ERROR: Нельзя подтвердить продажу 7 без позиций

-- Правильный путь: справочники есть -> создали продажу -> добавили позиции -> подтвердили.
CALL sp_add_item(7, 1, 2);
CALL sp_add_item(7, 3, 1);
SELECT * FROM sales WHERE sale_id = 7;       -- sale_total посчитан триггером
CALL sp_confirm_sale(7);
SELECT med_id, med_stock FROM medicines WHERE med_id IN (1, 3);   -- остатки списаны

-- Нельзя удалить подтверждённую продажу и вернуть её в черновик.
DELETE FROM sales WHERE sale_id = 7;
UPDATE sales SET sale_status = 'draft' WHERE sale_id = 7;

-- Нельзя удалить категорию, в которой есть лекарства (RESTRICT).
DELETE FROM categories WHERE cat_id = 1;

-- Сценарий 2. Транзакция: заказ из двух позиций, вторая не проходит - не создаётся ничего.
-- То же делает POST /api/orders/checkout.
BEGIN;
SELECT fn_create_sale(1);
-- подставьте номер, например 8
CALL sp_add_item(8, 2, 1);
CALL sp_add_item(8, 10, 1);          -- Цитрамон: на складе 0
ROLLBACK;
SELECT count(*) FROM sales;          -- число продаж не изменилось

-- Сценарий 3. Материализованное представление.
SELECT * FROM mv_revenue_by_category ORDER BY cat_id;
-- Что-то поменяли (например, подтвердили продажу 5):
CALL sp_confirm_sale(5);
SELECT * FROM mv_revenue_by_category ORDER BY cat_id;     -- ещё старое
REFRESH MATERIALIZED VIEW mv_revenue_by_category;
SELECT * FROM mv_revenue_by_category ORDER BY cat_id;     -- обновилось

-- Сценарий 4. Триггер аудита.
UPDATE medicines SET med_price = med_price + 10 WHERE med_id = 1;
SELECT log_time, log_table, log_op, log_old ->> 'med_price' AS old_price, log_new ->> 'med_price' AS new_price
FROM   audit_log
ORDER  BY log_id DESC
LIMIT  3;

-- Сценарий 5. Курсор.
SELECT fn_update_discounts();
SELECT cust_name, cust_discount FROM customers ORDER BY cust_id;
