-- Запускать отдельно, подключившись к базе postgres (не к pharmacy).
-- CREATE DATABASE нельзя выполнять внутри транзакции.
CREATE DATABASE pharmacy
    ENCODING 'UTF8'
    TEMPLATE template0
    LC_COLLATE 'Russian_Russia.1251'
    LC_CTYPE 'Russian_Russia.1251';

-- Если у вас Linux/macOS или будет ошибка про локаль, используйте простой вариант:
-- CREATE DATABASE pharmacy ENCODING 'UTF8';

-- После создания в pgAdmin откройте Query Tool именно на базе pharmacy.
COMMENT ON DATABASE pharmacy IS 'Учебный пример: аптека (рубежный контроль)';
