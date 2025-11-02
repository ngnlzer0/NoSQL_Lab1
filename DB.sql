-- =================================================================
-- Скрипт створення БД: E-commerce (Multi-Store)
-- Виконує Пункти 4, 5, 6
-- СУБД: PostgreSQL
-- =================================================================

-- -----------------------------------------------------
-- ПУНКТ 4: Реалізація Моделі (Створення Таблиць)
-- -----------------------------------------------------
-- Створюємо всі 16 сутностей


-- 1. Користувачі, Ролі та Магазини
CREATE TABLE Users (
    Id SERIAL PRIMARY KEY,
    FullName VARCHAR(255),
    Email VARCHAR(255) NOT NULL UNIQUE,
    PasswordHash VARCHAR(512) NOT NULL,
    CreatedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Вимога 3 (Soft Delete)
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE Roles (
    Id SERIAL PRIMARY KEY,
    RoleName VARCHAR(50) NOT NULL UNIQUE -- 'Admin', 'StoreManager', 'Customer'
);

CREATE TABLE UserRoles (
    UserId INT NOT NULL REFERENCES Users(Id) ON DELETE CASCADE,
    RoleId INT NOT NULL REFERENCES Roles(Id) ON DELETE CASCADE,
    PRIMARY KEY (UserId, RoleId)
);

CREATE TABLE Stores (
    Id SERIAL PRIMARY KEY,
    StoreName VARCHAR(255) NOT NULL,
    Address VARCHAR(500),
    CreatedAt TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE StoreStaff (
    UserId INT NOT NULL REFERENCES Users(Id) ON DELETE CASCADE,
    StoreId INT NOT NULL REFERENCES Stores(Id) ON DELETE CASCADE,
    PRIMARY KEY (UserId, StoreId)
);

-- 2. Каталог Товарів
CREATE TABLE Categories (
    Id SERIAL PRIMARY KEY,
    ParentCategoryId INT REFERENCES Categories(Id) ON DELETE SET NULL,
    Name VARCHAR(255) NOT NULL,
    CreatedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Вимога 3 (Аудит)
    ModifiedAt TIMESTAMPTZ,
    ModifiedById INT REFERENCES Users(Id)
);

CREATE TABLE Brands (
    Id SERIAL PRIMARY KEY,
    BrandName  VARCHAR(255) NOT NULL UNIQUE
);

CREATE TABLE Products (
    Id SERIAL PRIMARY KEY,
    BrandId INT REFERENCES Brands(Id),
    ProductName VARCHAR(500) NOT NULL,
    Description TEXT,
    CreatedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Вимога 3 (Soft Delete + Аудит)
    IsDeleted BOOLEAN NOT NULL DEFAULT FALSE,
    ModifiedAt TIMESTAMPTZ,
    ModifiedById INT REFERENCES Users(Id)
);

CREATE TABLE ProductCategories (
    ProductId INT NOT NULL REFERENCES Products(Id) ON DELETE CASCADE,
    CategoryId INT NOT NULL REFERENCES Categories(Id) ON DELETE CASCADE,
    PRIMARY KEY (ProductId, CategoryId)
);

-- 3. Інвентар (Ціни та Кількість)
CREATE TABLE StoreInventories (
    Id SERIAL PRIMARY KEY,
    StoreId INT NOT NULL REFERENCES Stores(Id) ON DELETE CASCADE,
    ProductId INT NOT NULL REFERENCES Products(Id) ON DELETE CASCADE,
    Price DECIMAL(10, 2) NOT NULL,
    Quantity INT NOT NULL DEFAULT 0,
    -- Вимога 3 (Аудит)
    ModifiedAt TIMESTAMPTZ,
    ModifiedById INT REFERENCES Users(Id),
    -- Композитний унікальний індекс (також вимога 6)
    UNIQUE(StoreId, ProductId)
);

-- 4. Замовлення та Оплата
CREATE TABLE ShippingAddresses (
    Id SERIAL PRIMARY KEY,
    UserId INT NOT NULL REFERENCES Users(Id) ON DELETE CASCADE,
    AddressLine1 VARCHAR(500) NOT NULL,
    City VARCHAR(100),
    PostalCode VARCHAR(20),
    IsDefault BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE Orders (
    Id SERIAL PRIMARY KEY,
    UserId INT NOT NULL REFERENCES Users(Id),
    StoreId INT NOT NULL REFERENCES Stores(Id),
    ShippingAddressId INT REFERENCES ShippingAddresses(Id),
    TotalAmount DECIMAL(10, 2) NOT NULL,
    CurrentStatus VARCHAR(50) NOT NULL DEFAULT 'Pending',
    CreatedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Вимога 3 (Аудит)
    ModifiedAt TIMESTAMPTZ,
    ModifiedById INT REFERENCES Users(Id)
);

CREATE TABLE OrderItems (
    Id SERIAL PRIMARY KEY,
    OrderId INT NOT NULL REFERENCES Orders(Id) ON DELETE CASCADE,
    ProductId INT NOT NULL REFERENCES Products(Id), -- Не видаляємо On Delete, щоб зберегти історію
    Quantity INT NOT NULL,
    PriceAtPurchase DECIMAL(10, 2) NOT NULL
);

CREATE TABLE OrderStatusHistory (
    Id SERIAL PRIMARY KEY,
    OrderId INT NOT NULL REFERENCES Orders(Id) ON DELETE CASCADE,
    Status VARCHAR(50) NOT NULL,
    ChangedAt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ChangedById INT REFERENCES Users(Id)
);

CREATE TABLE PaymentMethods (
    Id SERIAL PRIMARY KEY,
    MethodName VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE Payments (
    Id SERIAL PRIMARY KEY,
    OrderId INT NOT NULL REFERENCES Orders(Id),
    PaymentMethodId INT NOT NULL REFERENCES PaymentMethods(Id),
    Amount DECIMAL(10, 2) NOT NULL,
    PaymentDate TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    TransactionId VARCHAR(255)
);

-- -----------------------------------------------------
-- ПУНКТ 6: Створення Індексів (2+ типів)
-- -----------------------------------------------------
-- (Note: PRIMARY KEY та UNIQUE вже автоматично створюють індекси)

-- Тип 1: Стандартний B-Tree індекс (для FK та пошуку)
-- Прискорює пошук замовлень конкретного користувача
CREATE INDEX idx_orders_userid ON Orders(UserId);

-- Прискорює пошук товарів за назвою
CREATE INDEX idx_products_productname ON Products(ProductName);

-- Прискорює пошук інвентаря за товаром (знайти, в яких магазинах є товар)
CREATE INDEX idx_storeinventories_productid ON StoreInventories(ProductId);


-- Тип 2: Частковий (Partial) індекс
-- Це ідеально для 'Soft Delete'. Індекс містить лише активні
-- товари, що робить пошук по каталогу (99% запитів) надзвичайно швидким.
CREATE INDEX idx_products_active
ON Products(Id)
WHERE IsDeleted = FALSE;

-- -----------------------------------------------------
-- ПУНКТ 5: Створення Бізнес-Логіки (10+ об'єктів)
-- -----------------------------------------------------

-- Об'єкт 1: Допоміжна процедура для встановлення ID користувача
-- Код (C#) буде викликати її перед транзакцією
CREATE OR REPLACE PROCEDURE sp_set_current_user(p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    -- Встановлюємо змінну сесії. 'false' означає,
    -- що вона доступна лише в цій сесії/транзакції.
    PERFORM set_config('myapp.current_user_id', p_user_id::TEXT, false);
EXCEPTION
    -- Ігноруємо помилки, якщо set_config не вдалося (напр., в середовищі без прав)
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not set current_user_id';
END;
$$;


-- Об'єкт 2: Універсальна Тригерна Функція для Аудиту
CREATE OR REPLACE FUNCTION fn_update_audit_columns()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id INT;
BEGIN
   -- Намагаємось отримати ID користувача з налаштувань сесії
   BEGIN
        v_user_id := current_setting('myapp.current_user_id')::INT;
   EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL; -- Якщо не встановлено, залишаємо NULL
   END;

   -- Оновлюємо поля в рядку, що змінюється
   NEW.ModifiedAt := NOW();
   NEW.ModifiedById := v_user_id;
   
   RETURN NEW; -- Повертаємо змінений рядок для продовження операції UPDATE
END;
$$ LANGUAGE plpgsql;


-- Об'єкти 3-6: Тригери (4), що викликають функцію
-- (Спрацьовують тільки якщо дані РЕАЛЬНО змінилися)

-- 3. Тригер для Products
CREATE TRIGGER trg_products_audit
BEFORE UPDATE ON Products
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*) -- Оптимізація: не запускати, якщо нічого не змінилося
EXECUTE FUNCTION fn_update_audit_columns();

-- 4. Тригер для Categories
CREATE TRIGGER trg_categories_audit
BEFORE UPDATE ON Categories
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE FUNCTION fn_update_audit_columns();

-- 5. Тригер для StoreInventories (ціна/кількість)
CREATE TRIGGER trg_storeinventories_audit
BEFORE UPDATE ON StoreInventories
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE FUNCTION fn_update_audit_columns();

-- 6. Тригер для Orders (статус/сума)
CREATE TRIGGER trg_orders_audit
BEFORE UPDATE ON Orders
FOR EACH ROW
WHEN (OLD.* IS DISTINCT FROM NEW.*)
EXECUTE FUNCTION fn_update_audit_columns();


-- Об'єкти 7-9: Збережені Процедури (3) для бізнес-логіки
-- (Це те, що буде викликати наш C# код)

-- 7. Процедура для "Soft Delete" Товару
CREATE OR REPLACE PROCEDURE sp_product_soft_delete(p_product_id INT, p_user_id INT)
LANGUAGE plpgsql AS $$
BEGIN
    -- 1. Встановлюємо, ХТО виконує операцію (для тригера)
    CALL sp_set_current_user(p_user_id);
    
    -- 2. Виконуємо Soft Delete.
    -- Це запустить тригер trg_products_audit
    UPDATE Products
    SET IsDeleted = TRUE
    WHERE Id = p_product_id;
END;
$$;

-- 8. Процедура для оновлення інвентаря (ціна/кількість)
CREATE OR REPLACE PROCEDURE sp_inventory_update(
    p_store_id INT, 
    p_product_id INT, 
    p_new_price DECIMAL, 
    p_new_quantity INT,
    p_user_id INT
)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_set_current_user(p_user_id);
    
    UPDATE StoreInventories
    SET 
        Price = p_new_price,
        Quantity = p_new_quantity
    WHERE StoreId = p_store_id AND ProductId = p_product_id;
END;
$$;

-- 9. Процедура для зміни статусу Замовлення (з логуванням)
CREATE OR REPLACE PROCEDURE sp_order_change_status(
    p_order_id INT, 
    p_new_status VARCHAR,
    p_user_id INT
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Встановлюємо користувача для ОБОХ операцій
    CALL sp_set_current_user(p_user_id);
    
    -- 1. Оновлюємо статус в самому замовленні
    -- (Це запустить тригер trg_orders_audit)
    UPDATE Orders
    SET CurrentStatus = p_new_status
    WHERE Id = p_order_id;
    
    -- 2. Додаємо запис в історію (для детального логу)
    INSERT INTO OrderStatusHistory (OrderId, Status, ChangedById)
    VALUES (p_order_id, p_new_status, p_user_id);
END;
$$;


-- Об'єкти 10-11: Розрізи Даних / Views (2)
-- (Це те, звідки наш C# код буде читати дані)

-- 10. Розріз для активних товарів (для каталогу)
-- (Використовує наш частковий індекс idx_products_active)
CREATE OR REPLACE VIEW v_products_active AS
SELECT 
    p.Id,
    p.ProductName,
    p.Description,
    b.BrandName
FROM 
    Products p
LEFT JOIN 
    Brands b ON p.BrandId = b.Id
WHERE 
    p.IsDeleted = FALSE;


-- 11. Розріз для деталей товару в конкретному магазині
CREATE OR REPLACE VIEW v_store_product_details AS
SELECT 
    si.StoreId,
    s.StoreName,
    p.Id AS ProductId,
    p.ProductName,
    b.BrandName,
    c.Name AS CategoryName,
    si.Price,
    si.Quantity
FROM 
    StoreInventories si
JOIN 
    Stores s ON si.StoreId = s.Id
JOIN 
    Products p ON si.ProductId = p.Id
LEFT JOIN 
    Brands b ON p.BrandId = b.Id
LEFT JOIN 
    ProductCategories pc ON p.Id = pc.ProductId
LEFT JOIN 
    Categories c ON pc.CategoryId = c.Id
WHERE 
    p.IsDeleted = FALSE; -- Показуємо лише активні товари


-- =================================================================
-- Кінець скрипту
-- =================================================================