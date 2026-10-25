\echo '1. should WORK'
INSERT INTO accounts VALUES ('1001', 'HDFC0001234', 'Ravi', 10000);
\echo '2. should FAIL: negative balance'
INSERT INTO accounts VALUES ('1002', 'HDFC0001234', 'Test', -50);
\echo '3. should WORK'
INSERT INTO vpa_aliases (vpa, account_number) VALUES ('ravi@banka', '1001');
\echo '4. should FAIL: account does not exist'
INSERT INTO vpa_aliases (vpa, account_number) VALUES ('ghost@banka', '9999');
\echo '5. should WORK: first debit'
INSERT INTO ledger_entries (txn_id, rrn, account_number, entry_type, amount, balance_after)
VALUES ('TXN1', '123456789012', '1001', 'DEBIT', 250, 9750);
\echo '6. should FAIL: duplicate (txn_id, entry_type), the idempotency rule'
INSERT INTO ledger_entries (txn_id, rrn, account_number, entry_type, amount, balance_after)
VALUES ('TXN1', '123456789012', '1001', 'DEBIT', 250, 9750);
\echo '7. should FAIL: amount must be > 0'
INSERT INTO ledger_entries (txn_id, rrn, account_number, entry_type, amount, balance_after)
VALUES ('TXN2', '123456789013', '1001', 'DEBIT', 0, 9750);
\echo '8. should FAIL: invalid entry_type'
INSERT INTO ledger_entries (txn_id, rrn, account_number, entry_type, amount, balance_after)
VALUES ('TXN3', '123456789014', '1001', 'REFUND', 10, 9990);
\echo '9. should FAIL: ledger is append-only (update)'
UPDATE ledger_entries SET amount = 1 WHERE txn_id = 'TXN1';
\echo '10. should FAIL: ledger is append-only (delete)'
DELETE FROM ledger_entries WHERE txn_id = 'TXN1';
\echo 'Final state:'
SELECT * FROM ledger_entries;