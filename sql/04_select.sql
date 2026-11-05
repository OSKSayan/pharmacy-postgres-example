-- 1. GROUP BY + HAVING: клиенты, у которых два и более заказа
SELECT sale_cust_id, count(*) AS sales_count
FROM   sales
GROUP  BY sale_cust_id
HAVING count(*) >= 2;

-- 2. JOIN трёх таблиц: что входит в каждую продажу
SELECT s.sale_id, c.cust_name, m.med_name, i.item_qty, i.item_price
FROM   sales s
JOIN   customers  c ON c.cust_id = s.sale_cust_id
JOIN   sale_items i ON i.item_sale_id = s.sale_id
JOIN   medicines  m ON m.med_id = i.item_med_id
ORDER  BY s.sale_id, m.med_name;

-- 3. LEFT JOIN + IS NULL: клиенты, которые ничего не покупали
SELECT c.cust_id, c.cust_name
FROM   customers c
LEFT   JOIN sales s ON s.sale_cust_id = c.cust_id
WHERE  s.sale_id IS NULL;

-- 4. Самосоединение: подкатегория и её надкатегория
SELECT child.cat_name AS category, parent.cat_name AS parent_category
FROM   categories child
JOIN   categories parent ON parent.cat_id = child.cat_parent;

-- 5. NOT IN (вложенный запрос): лекарства, которые никогда не продавались
SELECT med_id, med_name
FROM   medicines
WHERE  med_id NOT IN (SELECT item_med_id FROM sale_items);

-- 6. Коррелированный запрос: лекарства дороже средней цены своей категории
SELECT m.med_name, m.med_price
FROM   medicines m
WHERE  m.med_price > (SELECT avg(m2.med_price)
                      FROM   medicines m2
                      WHERE  m2.med_cat_id = m.med_cat_id);

-- 7. EXISTS: клиенты, у которых есть хотя бы одна подтверждённая продажа
SELECT c.cust_name
FROM   customers c
WHERE  EXISTS (SELECT 1 FROM sales s
               WHERE  s.sale_cust_id = c.cust_id AND s.sale_status = 'confirmed');

-- 8. ANY: лекарства дороже хотя бы одного витамина
SELECT med_name, med_price
FROM   medicines
WHERE  med_price > ANY (SELECT med_price FROM medicines WHERE med_cat_id = 3);

-- 9. ALL: лекарства дороже всех обезболивающих
SELECT med_name, med_price
FROM   medicines
WHERE  med_price > ALL (SELECT med_price FROM medicines WHERE med_cat_id = 1);

-- 10. LIKE + ILIKE: поиск по части названия
SELECT * FROM medicines WHERE med_name ILIKE '%вит%';

-- 11. Регулярное выражение: названия, где есть цифры
SELECT med_name FROM medicines WHERE med_name ~ '[0-9]';

-- 12. BETWEEN + ORDER BY + LIMIT/OFFSET: страница результатов (товары 3-5 по цене)
SELECT med_name, med_price
FROM   medicines
WHERE  med_price BETWEEN 100 AND 700
ORDER  BY med_price DESC
LIMIT  3 OFFSET 2;

-- 13. CASE и вычисляемый столбец
SELECT med_name,
       med_price,
       CASE WHEN med_price < 150 THEN 'дёшево'
            WHEN med_price < 500 THEN 'средне'
            ELSE 'дорого' END AS price_class,
       med_price * med_stock AS stock_value
FROM   medicines;

-- 14. DISTINCT
SELECT DISTINCT sale_status FROM sales;

-- 15. Массив: лекарства с тегом "рецепт"; первый тег; количество тегов
SELECT med_name, med_tags[1] AS first_tag, array_length(med_tags, 1) AS tags_count
FROM   medicines
WHERE  'рецепт' = ANY (med_tags);

-- 16. unnest: развернуть массив в строки и посчитать, сколько раз встречается тег
SELECT tag, count(*) FROM medicines, unnest(med_tags) AS tag GROUP BY tag ORDER BY 2 DESC;

-- 17. jsonb: достать поле, отфильтровать по условию, проверить вхождение
SELECT med_name, med_info ->> 'форма' AS form, (med_info ->> 'дозировка_мг')::int AS mg
FROM   medicines
WHERE  med_info @> '{"рецепт": true}';

-- 18. jsonb: изменить значение поля
UPDATE medicines SET med_info = jsonb_set(med_info, '{рецепт}', 'false') WHERE med_name = 'Амоксициллин 500 мг' RETURNING med_name, med_info;
UPDATE medicines SET med_info = jsonb_set(med_info, '{рецепт}', 'true')  WHERE med_name = 'Амоксициллин 500 мг';
