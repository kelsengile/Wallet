-- Default data inserted once, when the database is first created.

INSERT INTO account_categories (name, sort_order) VALUES
  ('Everyday', 0),
  ('Savings', 1),
  ('Investments', 2),
  ('Debt', 3);

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