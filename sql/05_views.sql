-- 1. Обычное представление: продажи с именами клиентов. Сайт читает его, а не таблицы.
CREATE OR REPLACE VIEW v_sales_full AS
SELECT s.sale_id, s.sale_date, s.sale_status, c.cust_name, s.sale_total
FROM   sales s
JOIN   customers c ON c.cust_id = s.sale_cust_id;

SELECT * FROM v_sales_full ORDER BY sale_id;

-- 2. Второе представление: лекарства с категорией и стоимостью остатка.
CREATE OR REPLACE VIEW v_medicines_full AS
SELECT m.med_id, m.med_name, m.med_price, m.med_stock, cat.cat_name,
       m.med_price * m.med_stock AS stock_value
FROM   medicines m
JOIN   categories cat ON cat.cat_id = m.med_cat_id;

-- 3. CREATE OR REPLACE: можно добавить столбец В КОНЕЦ списка (порядок и имена старых менять нельзя).
CREATE OR REPLACE VIEW v_medicines_full AS
SELECT m.med_id, m.med_name, m.med_price, m.med_stock, cat.cat_name,
       m.med_price * m.med_stock AS stock_value,
       m.med_tags
FROM   medicines m
JOIN   categories cat ON cat.cat_id = m.med_cat_id;

-- 4. Материализованное представление: выручка по категориям (только не черновики).
CREATE MATERIALIZED VIEW mv_revenue_by_category AS
SELECT cat.cat_id, cat.cat_name,
       COALESCE(sum(x.item_qty * x.item_price), 0) AS revenue
FROM   categories cat
LEFT   JOIN medicines m ON m.med_cat_id = cat.cat_id
LEFT   JOIN (sale_items x JOIN sales s ON s.sale_id = x.item_sale_id AND s.sale_status <> 'draft')
       ON x.item_med_id = m.med_id
GROUP  BY cat.cat_id, cat.cat_name;

-- Уникальный индекс нужен для REFRESH ... CONCURRENTLY.
CREATE UNIQUE INDEX ux_mv_revenue_cat ON mv_revenue_by_category (cat_id);

-- 5. Жизненный цикл: добавили данные -> отчёт НЕ изменился -> REFRESH -> изменился.
SELECT * FROM mv_revenue_by_category ORDER BY cat_id;

UPDATE sales SET sale_status = 'confirmed' WHERE sale_id = 5;  -- черновик 5 становится подтверждённым

SELECT * FROM mv_revenue_by_category ORDER BY cat_id;          -- старые цифры

REFRESH MATERIALIZED VIEW mv_revenue_by_category;

SELECT * FROM mv_revenue_by_category ORDER BY cat_id;          -- новые цифры

UPDATE sales SET sale_status = 'draft' WHERE sale_id = 5;      -- вернуть как было (до триггеров можно)
REFRESH MATERIALIZED VIEW mv_revenue_by_category;

-- 6. Параллельное обновление, пока другие читают отчёт (нужен уникальный индекс).
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_revenue_by_category;

-- 7. Переименование представлений.
ALTER VIEW v_medicines_full RENAME TO v_medicines_report;
ALTER VIEW v_medicines_report RENAME TO v_medicines_full;
ALTER MATERIALIZED VIEW mv_revenue_by_category RENAME TO mv_revenue_by_cat;
ALTER MATERIALIZED VIEW mv_revenue_by_cat RENAME TO mv_revenue_by_category;

-- 8. WITH NO DATA: представление создано, но не заполнено.
CREATE MATERIALIZED VIEW mv_discount_customers AS
SELECT cust_id, cust_name, cust_discount FROM customers WHERE cust_discount > 0
WITH NO DATA;

SELECT * FROM mv_discount_customers;   -- ошибка: представление не заполнено

REFRESH MATERIALIZED VIEW mv_discount_customers;

SELECT * FROM mv_discount_customers;   -- работает (пока пусто)

-- 9. Посмотреть, какие материализованные представления есть и заполнены ли они.
SELECT matviewname, ispopulated FROM pg_matviews;
