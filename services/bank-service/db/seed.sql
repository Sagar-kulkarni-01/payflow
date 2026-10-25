INSERT INTO accounts (account_number, ifsc_code, account_holder_name, balance) VALUES
  ('1001', 'HDFC0001234', 'Ravi',  10000),
  ('1002', 'HDFC0001234', 'Meera',  2500);

INSERT INTO vpa_aliases (vpa, account_number) VALUES
  ('ravi@banka',  '1001'),
  ('meera@banka', '1002');