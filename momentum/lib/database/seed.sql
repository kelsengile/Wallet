-- Default data inserted once, when the database is first created.

INSERT INTO account_categories (name, sort_order) VALUES
  ('Everyday', 0),
  ('Savings', 1),
  ('Investments', 2),
  ('Debt', 3);

-- The first account the user sees. Starts at zero.
INSERT INTO accounts (name, type, category_id, initial_balance) VALUES 
  ('Cash', 'cash', (SELECT id FROM account_categories WHERE name = 'Everyday'), 0 );

INSERT INTO categories (name, kind) VALUES
  ('Food & Dining', 'expense'),
  ('Groceries', 'expense'),
  ('Transport', 'expense'),
  ('Bills & Utilities', 'expense'),
  ('Shopping', 'expense'),
  ('Health', 'expense'),
  ('Entertainment', 'expense'),
  ('Education', 'expense'),
  ('Other', 'expense'),
  ('Salary', 'income'),
  ('Business', 'income'),
  ('Gift', 'income'),
  ('Interest', 'income'),
  ('Other', 'income');