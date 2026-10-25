-- Momentum local database schema (version 1)
-- Money is stored as whole centavos (INTEGER) so there are no rounding errors.
-- Dates are stored as milliseconds since the Unix epoch (INTEGER).
-- Rows with deleted_at set are in the Trash. NULL means the row is active.
-- Keep this file free of semicolons inside comments and strings, because
-- the app splits the script on semicolons.

-- ---------- Account categories (user-editable groups) ----------
CREATE TABLE account_categories (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL UNIQUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000)
);

-- ---------- Accounts ----------
CREATE TABLE accounts (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name            TEXT    NOT NULL,
  type            TEXT    NOT NULL
                  CHECK (type IN ('cash', 'bank', 'e_wallet', 'credit_card', 'investment', 'other')),
  category_id     INTEGER REFERENCES account_categories (id) ON DELETE SET NULL,
  initial_balance INTEGER NOT NULL DEFAULT 0,
  card_theme      TEXT,
  note            TEXT,
  created_at      INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000),
  updated_at      INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000),
  deleted_at      INTEGER
);

CREATE INDEX idx_accounts_category ON accounts (category_id);
CREATE INDEX idx_accounts_deleted  ON accounts (deleted_at);

-- ---------- Transaction categories (Food, Salary, ...) ----------
CREATE TABLE categories (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  name       TEXT    NOT NULL,
  kind       TEXT    NOT NULL CHECK (kind IN ('income', 'expense')),
  icon       TEXT,
  color      INTEGER,
  created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000),
  deleted_at INTEGER,
  UNIQUE (name, kind)
);

-- ---------- Transactions ----------
-- type: income, expense, transfer or reminder
-- account_id    = the account money comes from (or goes into for income)
-- to_account_id = destination account, only used by transfers
-- Reminders never change a balance.
CREATE TABLE transactions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  type          TEXT    NOT NULL
                CHECK (type IN ('income', 'expense', 'transfer', 'reminder')),
  title         TEXT    NOT NULL,
  amount        INTEGER NOT NULL CHECK (amount > 0),
  date          INTEGER NOT NULL,
  category_id   INTEGER REFERENCES categories (id) ON DELETE SET NULL,
  account_id    INTEGER NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
  to_account_id INTEGER REFERENCES accounts (id) ON DELETE CASCADE,
  note          TEXT,
  image_path    TEXT,
  created_at    INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000),
  updated_at    INTEGER NOT NULL DEFAULT (CAST(strftime('%s', 'now') AS INTEGER) * 1000),
  deleted_at    INTEGER,
  CHECK (
    (type = 'transfer' AND to_account_id IS NOT NULL AND to_account_id <> account_id)
    OR (type <> 'transfer' AND to_account_id IS NULL)
  )
);

CREATE INDEX idx_transactions_date       ON transactions (date DESC);
CREATE INDEX idx_transactions_account    ON transactions (account_id);
CREATE INDEX idx_transactions_to_account ON transactions (to_account_id);
CREATE INDEX idx_transactions_category   ON transactions (category_id);
CREATE INDEX idx_transactions_type       ON transactions (type);
CREATE INDEX idx_transactions_deleted    ON transactions (deleted_at);

-- ---------- Current balance per account ----------
-- initial_balance plus income, minus expenses, plus/minus transfers.
-- Trashed transactions and reminders are ignored.
CREATE VIEW account_balances AS
SELECT
  a.id AS account_id,
  a.initial_balance + COALESCE(SUM(
    CASE
      WHEN t.deleted_at IS NOT NULL THEN 0
      WHEN t.type = 'income'   AND t.account_id    = a.id THEN  t.amount
      WHEN t.type = 'expense'  AND t.account_id    = a.id THEN -t.amount
      WHEN t.type = 'transfer' AND t.account_id    = a.id THEN -t.amount
      WHEN t.type = 'transfer' AND t.to_account_id = a.id THEN  t.amount
      ELSE 0
    END
  ), 0) AS balance
FROM accounts a
LEFT JOIN transactions t
  ON t.account_id = a.id OR t.to_account_id = a.id
GROUP BY a.id;