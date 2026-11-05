-- 1. Явный курсор в PL/pgSQL: пересчитать скидки клиентов по сумме покупок.
CREATE OR REPLACE FUNCTION fn_update_discounts()
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    cur CURSOR FOR
        SELECT c.cust_id, COALESCE(sum(s.sale_total), 0) AS spent
        FROM   customers c
        LEFT   JOIN sales s ON s.sale_cust_id = c.cust_id AND s.sale_status <> 'draft'
        GROUP  BY c.cust_id
        ORDER  BY c.cust_id;
    rec      record;
    new_disc integer;
    changed  integer := 0;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;

        new_disc := CASE WHEN rec.spent >= 1500 THEN 15
                         WHEN rec.spent >= 800  THEN 10
                         WHEN rec.spent >= 300  THEN 5
                         ELSE 0 END;

        UPDATE customers SET cust_discount = new_disc
        WHERE  cust_id = rec.cust_id AND cust_discount <> new_disc;

        IF FOUND THEN
            changed := changed + 1;
        END IF;
    END LOOP;
    CLOSE cur;
    RETURN changed;
END;
$$;

SELECT fn_update_discounts();
SELECT cust_name, cust_discount FROM customers ORDER BY cust_id;

-- 2. Прокручиваемый курсор на уровне SQL. Работает только внутри транзакции.
BEGIN;

DECLARE c1 SCROLL CURSOR FOR
    SELECT med_id, med_name FROM medicines ORDER BY med_id;

FETCH NEXT  FROM c1;   -- первая строка
FETCH 3     FROM c1;   -- следующие три
FETCH PRIOR FROM c1;   -- шаг назад
FETCH FIRST FROM c1;   -- в начало
FETCH LAST  FROM c1;   -- в конец

CLOSE c1;
COMMIT;
