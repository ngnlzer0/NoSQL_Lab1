-- =================================================================
-- Скрипт Ініціалізації Даних (Seed Script)
-- =================================================================


-- 1. Базові довідники (не мають залежностей)
INSERT INTO Roles (RoleName) VALUES ('Admin'), ('StoreManager'), ('Customer') 
ON CONFLICT (RoleName) DO NOTHING;

INSERT INTO PaymentMethods (MethodName) VALUES ('Credit Card'), ('Cash on Delivery') 
ON CONFLICT (MethodName) DO NOTHING;

INSERT INTO Brands (BrandName) VALUES ('Apple'), ('Samsung'), ('Sony') 
ON CONFLICT (BrandName) DO NOTHING;

-- 2. Категорії (мають залежність самі від себе)
-- Припускаємо, що 'Electronics' отримає ID 1
INSERT INTO Categories (Name, ParentCategoryId) VALUES ('Electronics', NULL);
-- Припускаємо, що 'Phones' і 'Computers' будуть пов'язані з ID 1
INSERT INTO Categories (Name, ParentCategoryId) VALUES 
('Phones', (SELECT Id FROM Categories WHERE Name = 'Electronics')), 
('Computers', (SELECT Id FROM Categories WHERE Name = 'Electronics'));

-- 3. Користувачі
-- (Паролі тут просто плейсхолдери, у реальному додатку це будуть хеші)
INSERT INTO Users (FullName, Email, PasswordHash) VALUES
('Admin User', 'admin@example.com', 'hash_placeholder_123'), -- Отримає ID 1
('Manager User', 'manager@example.com', 'hash_placeholder_456'), -- Отримає ID 2
('Customer User', 'customer@example.com', 'hash_placeholder_789'); -- Отримає ID 3

-- 4. Призначення Ролей Користувачам
-- (Використовуємо підзапити, щоб знайти ID за назвами/email)
INSERT INTO UserRoles (UserId, RoleId) VALUES
((SELECT Id FROM Users WHERE Email = 'admin@example.com'), (SELECT Id FROM Roles WHERE RoleName = 'Admin')),
((SELECT Id FROM Users WHERE Email = 'manager@example.com'), (SELECT Id FROM Roles WHERE RoleName = 'StoreManager')),
((SELECT Id FROM Users WHERE Email = 'customer@example.com'), (SELECT Id FROM Roles WHERE RoleName = 'Customer'));

-- 5. Магазини
INSERT INTO Stores (StoreName, Address) VALUES
('Flagship Store', 'Kyiv, Khreshchatyk, 1'); -- Отримає ID 1

-- 6. Призначення Персоналу в Магазин
-- (Призначимо нашого Менеджера (ID 2) в Магазин (ID 1))
INSERT INTO StoreStaff (UserId, StoreId) VALUES
((SELECT Id FROM Users WHERE Email = 'manager@example.com'), (SELECT Id FROM Stores WHERE StoreName = 'Flagship Store'));

-- 7. Товари
INSERT INTO Products (ProductName, BrandId, Description) VALUES
('iPhone 15 Pro', (SELECT Id FROM Brands WHERE BrandName = 'Apple'), 'Newest Apple phone'), -- Отримає ID 1
('Galaxy S24 Ultra', (SELECT Id FROM Brands WHERE BrandName = 'Samsung'), 'Newest Samsung phone'), -- Отримає ID 2
('MacBook Pro 16"', (SELECT Id FROM Brands WHERE BrandName = 'Apple'), 'Apple M4 Pro laptop'); -- Отримає ID 3

-- 8. Призначення Категорій Товарам
INSERT INTO ProductCategories (ProductId, CategoryId) VALUES
((SELECT Id FROM Products WHERE ProductName = 'iPhone 15 Pro'), (SELECT Id FROM Categories WHERE Name = 'Phones')),
((SELECT Id FROM Products WHERE ProductName = 'Galaxy S24 Ultra'), (SELECT Id FROM Categories WHERE Name = 'Phones')),
((SELECT Id FROM Products WHERE ProductName = 'MacBook Pro 16"'), (SELECT Id FROM Categories WHERE Name = 'Computers'));

-- 9. Інвентар (Найважливіше!)
-- Додаємо товари в наш 'Flagship Store' (ID 1)
INSERT INTO StoreInventories (StoreId, ProductId, Price, Quantity, ModifiedById) VALUES
(1, 1, 1299.99, 50, (SELECT Id FROM Users WHERE Email = 'admin@example.com')), -- iPhone
(1, 2, 1199.99, 40, (SELECT Id FROM Users WHERE Email = 'admin@example.com')), -- Galaxy
(1, 3, 2499.99, 20, (SELECT Id FROM Users WHERE Email = 'admin@example.com')); -- MacBook


-- Оновимо послідовності, якщо ми вставляли дані вручну (хороша практика)
SELECT setval('users_id_seq', (SELECT MAX(Id) FROM Users));
SELECT setval('categories_id_seq', (SELECT MAX(Id) FROM Categories));
SELECT setval('stores_id_seq', (SELECT MAX(Id) FROM Stores));
SELECT setval('products_id_seq', (SELECT MAX(Id) FROM Products));
-- і т.д. для всіх таблиць з SERIAL