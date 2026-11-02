-- Tables created once, when the database is first created.
-- Money is stored as whole centavos.
-- Every statement is IF NOT EXISTS, so it is also safe to run on an
-- existing database (helper.dart uses that to add missing tables).

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
  note_title TEXT,
  note_body TEXT,
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
  title TEXT,
  note TEXT,
  image_path TEXT,
  date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TEXT
);

CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  title TEXT NOT NULL,
  amount INTEGER NOT NULL,
  category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  account_id INTEGER REFERENCES accounts(id) ON DELETE SET NULL,
  due_date TEXT NOT NULL,
  repeat_rule TEXT NOT NULL DEFAULT 'none'
    CHECK (repeat_rule IN ('none', 'daily', 'weekly', 'monthly', 'yearly')),
  note TEXT,
  image_path TEXT,
  done INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
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