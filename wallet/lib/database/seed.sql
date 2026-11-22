-- Default data inserted once, when the database is first created.

-- ---------- Account types ----------
INSERT INTO account_types (name) VALUES
  ('Cash'),
  ('Bank'),
  ('Digital Bank'),
  ('Credit'),
  ('E-Wallet'),
  ('Investment'),
  ('Assets'),
  ('Debt'),
  ('Business');

-- ---------- Account categories ----------
INSERT INTO account_categories (name, sort_order) VALUES
  ('Personal', 0),
  ('Family', 1),
  ('Savings', 2),
  ('Future', 3),
  ('Work', 4),
  ('Travel', 5),
  ('Health', 6),
  ('Investment', 7),
  ('Debt', 8),
  ('Emergency', 9),
  ('Spending', 10);

-- The first account the user sees. Starts at zero.
INSERT INTO accounts (name, type_id, category_id, initial_balance) VALUES
  ('Cash',
   (SELECT id FROM account_types WHERE name = 'Cash'),
   (SELECT id FROM account_categories WHERE name = 'Personal'),
   0);

-- ---------- Transaction categories ----------
INSERT INTO categories (name, kind) VALUES
  ('Salary', 'income'),
  ('Bonus', 'income'),
  ('Commission', 'income'),
  ('Allowance', 'income'),
  ('Freelance', 'income'),
  ('Business', 'income'),
  ('Investment', 'income'),
  ('Gift', 'income'),
  ('Scholarship', 'income'),
  ('Refund', 'income'),
  ('Loan', 'income'),
  ('Miscellaneous', 'income'),
  ('Food', 'expense'),
  ('Transportation', 'expense'),
  ('Shopping', 'expense'),
  ('Bills', 'expense'),
  ('Health', 'expense'),
  ('Education', 'expense'),
  ('Entertainment', 'expense'),
  ('Tax', 'expense'),
  ('Debt', 'expense'),
  ('Gift', 'expense'),
  ('Travel', 'expense'),
  ('Sports', 'expense'),
  ('Miscellaneous', 'expense'),
  ('Transfer', 'transfer');