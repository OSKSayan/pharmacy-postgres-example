-- Скрипт можно запускать повторно: сначала всё удаляется, потом создаётся заново.
DROP TABLE IF EXISTS audit_log, sale_items, sales, medicines, customers, categories CASCADE;

-- Категории лекарств. cat_parent ссылается на эту же таблицу (иерархия).
CREATE TABLE categories (
    cat_id     integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cat_name   varchar(60) NOT NULL UNIQUE,
    cat_parent integer     REFERENCES categories (cat_id) ON DELETE SET NULL
);

-- Лекарства. Есть массив (med_tags) и jsonb (med_info).
CREATE TABLE medicines (
    med_id     integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    med_name   varchar(80)   NOT NULL,
    med_price  numeric(10,2) NOT NULL CHECK (med_price >= 0),
    med_stock  integer       NOT NULL DEFAULT 0 CHECK (med_stock >= 0),
    med_cat_id integer       NOT NULL REFERENCES categories (cat_id) ON DELETE RESTRICT,
    med_tags   text[]        NOT NULL DEFAULT '{}',
    med_info   jsonb         NOT NULL DEFAULT '{}'
);

CREATE TABLE customers (
    cust_id       integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cust_name     varchar(80) NOT NULL,
    cust_phone    varchar(20) UNIQUE,
    cust_discount integer     NOT NULL DEFAULT 0 CHECK (cust_discount BETWEEN 0 AND 50)
);

-- Главный документ. Статус двигается только вперёд: draft -> confirmed -> closed.
CREATE TABLE sales (
    sale_id      integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sale_cust_id integer       NOT NULL REFERENCES customers (cust_id) ON DELETE RESTRICT,
    sale_date    date          NOT NULL DEFAULT current_date CHECK (sale_date <= current_date),
    sale_status  varchar(12)   NOT NULL DEFAULT 'draft'
                 CHECK (sale_status IN ('draft', 'confirmed', 'closed')),
    sale_total   numeric(12,2) NOT NULL DEFAULT 0
);

-- Строки документа. Удаляем продажу - строки удаляются каскадом.
CREATE TABLE sale_items (
    item_id      integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_sale_id integer       NOT NULL REFERENCES sales (sale_id) ON DELETE CASCADE,
    item_med_id  integer       NOT NULL REFERENCES medicines (med_id) ON DELETE RESTRICT,
    item_qty     integer       NOT NULL CHECK (item_qty > 0),
    item_price   numeric(10,2) NOT NULL CHECK (item_price >= 0),
    UNIQUE (item_sale_id, item_med_id)
);

-- Журнал аудита: сюда пишут триггеры (скрипт 09).
CREATE TABLE audit_log (
    log_id    integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    log_table text        NOT NULL,
    log_op    text        NOT NULL,
    log_old   jsonb,
    log_new   jsonb,
    log_time  timestamptz NOT NULL DEFAULT now(),
    log_user  text        NOT NULL DEFAULT current_user
);
