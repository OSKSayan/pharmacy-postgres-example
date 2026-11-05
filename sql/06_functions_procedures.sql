-- ФУНКЦИЯ (SQL, возвращает одно значение): цена лекарства с учётом скидки клиента.
CREATE OR REPLACE FUNCTION fn_price_with_discount(p_med integer, p_cust integer)
RETURNS numeric
LANGUAGE sql
AS $$
    SELECT round(m.med_price * (100 - c.cust_discount) / 100.0, 2)
    FROM   medicines m, customers c
    WHERE  m.med_id = p_med AND c.cust_id = p_cust;
$$;

SELECT fn_price_with_discount(1, 1);

-- ФУНКЦИЯ (PL/pgSQL, переменная + SELECT ... INTO): сумма продажи.
CREATE OR REPLACE FUNCTION fn_sale_total(p_sale integer)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_total numeric;
BEGIN
    SELECT COALESCE(sum(item_qty * item_price), 0) INTO v_total
    FROM   sale_items
    WHERE  item_sale_id = p_sale;
    RETURN v_total;
END;
$$;

SELECT fn_sale_total(1);

-- ФУНКЦИЯ (возвращает таблицу): самые продаваемые лекарства.
CREATE OR REPLACE FUNCTION fn_top_medicines(p_limit integer DEFAULT 3)
RETURNS TABLE (med_id integer, med_name text, qty bigint)
LANGUAGE sql
AS $$
    SELECT m.med_id, m.med_name::text, sum(i.item_qty)
    FROM   sale_items i
    JOIN   medicines m ON m.med_id = i.item_med_id
    GROUP  BY m.med_id, m.med_name
    ORDER  BY sum(i.item_qty) DESC, m.med_id
    LIMIT  p_limit;
$$;

SELECT * FROM fn_top_medicines(3);

-- ФУНКЦИЯ: создать пустую продажу (черновик) и вернуть её номер.
CREATE OR REPLACE FUNCTION fn_create_sale(p_cust integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_id integer;
BEGIN
    INSERT INTO sales (sale_cust_id) VALUES (p_cust) RETURNING sale_id INTO v_id;
    RETURN v_id;
END;
$$;

-- ПРОЦЕДУРА: добавить позицию в продажу. Если такое лекарство уже есть - увеличить количество.
CREATE OR REPLACE PROCEDURE sp_add_item(p_sale integer, p_med integer, p_qty integer)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cust  integer;
    v_price numeric;
BEGIN
    SELECT sale_cust_id INTO v_cust FROM sales WHERE sale_id = p_sale;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Продажа % не найдена', p_sale;
    END IF;

    v_price := fn_price_with_discount(p_med, v_cust);
    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Лекарство % не найдено', p_med;
    END IF;

    INSERT INTO sale_items (item_sale_id, item_med_id, item_qty, item_price)
    VALUES (p_sale, p_med, p_qty, v_price)
    ON CONFLICT (item_sale_id, item_med_id)
    DO UPDATE SET item_qty = sale_items.item_qty + EXCLUDED.item_qty;
END;
$$;

-- ПРОЦЕДУРА: подтвердить продажу. Списывает остатки со склада.
-- Правила (пустая продажа, неверный переход статуса) проверяет триггер из скрипта 09.
CREATE OR REPLACE PROCEDURE sp_confirm_sale(p_sale integer)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE sales SET sale_status = 'confirmed' WHERE sale_id = p_sale;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Продажа % не найдена', p_sale;
    END IF;

    UPDATE medicines m
    SET    med_stock = m.med_stock - i.item_qty
    FROM   sale_items i
    WHERE  i.item_sale_id = p_sale AND i.item_med_id = m.med_id;
END;
$$;

-- ПРОЦЕДУРА: удалить черновик продажи (с обработкой ошибки).
CREATE OR REPLACE PROCEDURE sp_delete_draft(p_sale integer)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM sales WHERE sale_id = p_sale;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Продажа % не найдена', p_sale;
    END IF;
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Продажу % нельзя удалить: есть связанные записи', p_sale;
END;
$$;

-- Вызов процедур: CALL (не SELECT).
-- CALL sp_add_item(5, 3, 2);
