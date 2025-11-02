import psycopg
from psycopg.rows import dict_row # Дозволяє отримувати дані у вигляді "словників" (dict)
from decimal import Decimal # Для коректної роботи з грошима (полем Price)
import sys # Для виводу помилок

# =================================================================
# 1. КЛАСИ РЕПОЗИТОРІЇВ
# =================================================================

class InventoryRepository:
    """
    Цей репозиторій відповідає за логіку ЗМІНИ даних в інвентарі.
    Він викликає Збережені Процедури.
    """
    def __init__(self, cursor):
        self._cursor = cursor

    def update_stock(self, store_id: int, product_id: int, new_price: Decimal, new_quantity: int, user_id: int):
        print(f"  > [Repo] Виклик CALL sp_inventory_update(...) для ProductID: {product_id}")
        
        sql = "CALL sp_inventory_update(%s, %s, %s, %s, %s)"
        
        self._cursor.execute(sql, (store_id, product_id, new_price, new_quantity, user_id))


class ProductViewRepository:
    """
    Цей репозиторій відповідає за логіку ЧИТАННЯ даних про товари.
    Він читає дані з Розрізів (Views).
    """
    def __init__(self, cursor):
        self._cursor = cursor
        self._cursor.row_factory = dict_row 

    def get_store_catalog(self, store_id: int):
        print(f"  > [Repo] Виклик SELECT * FROM v_store_product_details...")
        
        sql = "SELECT * FROM v_store_product_details WHERE storeid = %s"
        
        self._cursor.execute(sql, (store_id,))
        return self._cursor.fetchall()


# =================================================================
# 2. КЛАС UNIT OF WORK
# =================================================================

class UnitOfWork:
    """
    Керує з'єднанням з БД та транзакцією.
    Надає доступ до репозиторіїв.
    """
    def __init__(self, connection_string: str):
        self._connection_string = connection_string
        self._connection = None
        self._cursor = None
        self._committed = False

    def __enter__(self):
        self._connection = psycopg.connect(self._connection_string)
        self._cursor = self._connection.cursor()
        
        self.inventories = InventoryRepository(self._cursor)
        self.product_catalog = ProductViewRepository(self._cursor)
        
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if exc_type is not None:
            print(f"\n--- X. ПОМИЛКА! Відкочуємо зміни (Rollback)... ---", file=sys.stderr)
            print(f"    Деталі: {exc_value}", file=sys.stderr)
            self._connection.rollback()
        else:
            if self._committed:
                print("\n--- 3. Зміни успішно збережено! (Commit) ---")
            else:
                print("\n--- ! УВАГА! Зміни не збережено (Rollback, бо 'complete()' не викликано) ---", file=sys.stderr)
                self._connection.rollback()
        
        if self._cursor:
            self._cursor.close()
        if self._connection:
            self._connection.close()

    def set_current_user(self, user_id: int):
        """Встановлює ID користувача для тригерів аудиту в БД."""
        print(f"  > [UoW] Виклик CALL sp_set_current_user({user_id})")
        self._cursor.execute("CALL sp_set_current_user(%s)", (user_id,))
    
    def complete(self):
        """Фіксує (commit) транзакцію."""
        self._connection.commit()
        self._committed = True


# =================================================================
# 3. ВИКОРИСТАННЯ (Головний код)
# =================================================================

# ВАЖЛИВО: Вкажіть тут ваш рядок підключення до PostgreSQL
# (Замініть 'your_password' на ваш пароль)
CONNECTION_STRING = "host=localhost dbname=multi_store_db user=postgres password=1234qwer"

# ID користувача, від імені якого ми працюємо (це наш "Manager User", ID 2)
CURRENT_USER_ID = 2
# ID магазину, в якому ми працюємо ("Flagship Store", ID 1)
STORE_ID = 1
# ID товару, який будемо оновлювати ("iPhone 15 Pro", ID 1)
PRODUCT_ID_TO_UPDATE = 1

def main():
    print("--- Запуск E-commerce App (Python) ---")

    try:
        with UnitOfWork(CONNECTION_STRING) as uow:
        
            print("\n--- 1. Читаємо поточний каталог (через View)... ---")
            
            products = uow.product_catalog.get_store_catalog(STORE_ID)
            for p in products:
                print(f"  > {p['productname']}: {p['price']} ({p['quantity']} шт.)")
            
            print("\n--- 2. Оновлюємо ціну iPhone (через Stored Procedure)... ---")

            uow.set_current_user(CURRENT_USER_ID)
            
            uow.inventories.update_stock(
                store_id=STORE_ID,
                product_id=PRODUCT_ID_TO_UPDATE,
                new_price=Decimal("1150.00"), # Нова ціна
                new_quantity=25,             # Нова кількість
                user_id=CURRENT_USER_ID
            )

            uow.complete()
            
    except psycopg.Error as e:
        print(f"\nПОМИЛКА БАЗИ ДАНИХ:\n{e}", file=sys.stderr)
    except Exception as e:
        print(f"\nЗАГАЛЬНА ПОМИЛКА:\n{e}", file=sys.stderr)


    # === ПЕРЕВІРКА ===
    print("\n--- 4. Перевіряємо дані в БД (читаємо знову)... ---")

    try:
        with UnitOfWork(CONNECTION_STRING) as uow:
            products = uow.product_catalog.get_store_catalog(STORE_ID)
            for p in products:
                print(f" > {p['productname']}: {p['price']} ({p['quantity']} шт.)")
    except Exception as e:
        print(f"Не вдалося перевірити дані: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()