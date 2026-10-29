-- Tables created once, when the database is first created.
-- Money is stored as whole centavos.

CREATE TABLE IF NOT EXISTS account_types (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  icon TEXT
);

CREATE TABLE IF NOT EXISTS account_categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  icon TEXT
);

CREATE TABLE IF NOT EXISTS accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  type_id INTEGER NOT NULL REFERENCES account_types(id),
  category_id INTEGER NOT NULL REFERENCES account_categories(id),
  initial_balance INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
  icon TEXT,
  UNIQUE (name, kind)
);

CREATE TABLE IF NOT EXISTS transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'transfer')),
  amount INTEGER NOT NULL,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  to_account_id INTEGER REFERENCES accounts(id),
  category_id INTEGER REFERENCES categories(id),
  note TEXT,
  date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT
);

CREATE VIEW IF NOT EXISTS account_balances AS
SELECT
  a.id AS account_id,
  a.initial_balance
    + COALESCE((SELECT SUM(t.amount) FROM transactions t
                WHERE t.account_id = a.id AND t.type = 'income'
                  AND t.deleted_at IS NULL), 0)
    - COALESCE((SELECT SUM(t.amount) FROM transactions t
                WHERE t.account_id = a.id AND t.type = 'expense'
                  AND t.deleted_at IS NULL), 0)
    - COALESCE((SELECT SUM(t.amount) FROM transactions t
                WHERE t.account_id = a.id AND t.type = 'transfer'
                  AND t.deleted_at IS NULL), 0)
    + COALESCE((SELECT SUM(t.amount) FROM transactions t
                WHERE t.to_account_id = a.id AND t.type = 'transfer'
                  AND t.deleted_at IS NULL), 0) AS balance
FROM accounts a