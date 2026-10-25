-- ============================================================
-- PayFlow bank-service schema (one bank = one database)
-- ============================================================

-- 1. ACCOUNTS: the bank's current view of each account.
CREATE TABLE accounts (
    account_number      TEXT PRIMARY KEY,                 -- stable id, text to keep leading zeros
    ifsc_code           CHAR(11) NOT NULL,
    account_holder_name TEXT NOT NULL,
    balance             NUMERIC(14, 2) NOT NULL DEFAULT 0
                        CHECK (balance >= 0),             -- DB refuses overdraft, whatever the code does
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. VPA ALIASES: a VPA is an alias, many can point to one account.
CREATE TABLE vpa_aliases (
    vpa            TEXT PRIMARY KEY,                      -- e.g. ravi@banka
    account_number TEXT NOT NULL REFERENCES accounts(account_number),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_vpa_aliases_account ON vpa_aliases(account_number);

-- 3. LEDGER: one immutable row per money movement.
CREATE TABLE ledger_entries (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    txn_id         TEXT NOT NULL,                         -- the payment this belongs to
    rrn            CHAR(12) NOT NULL CHECK (rrn ~ '^[0-9]{12}$'),  -- shared reference for recon/disputes
    account_number TEXT NOT NULL REFERENCES accounts(account_number),
    entry_type     TEXT NOT NULL
                   CHECK (entry_type IN ('DEBIT', 'CREDIT', 'REVERSAL')),
    amount         NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    balance_after  NUMERIC(14, 2) NOT NULL CHECK (balance_after >= 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- IDEMPOTENCY: a transaction can have at most one entry of each type.
    CONSTRAINT uq_ledger_txn_entry UNIQUE (txn_id, entry_type)
);
CREATE INDEX idx_ledger_rrn ON ledger_entries(rrn);
CREATE INDEX idx_ledger_account_time ON ledger_entries(account_number, created_at);

-- 4. APPEND-ONLY: the ledger can never be edited or deleted.
CREATE FUNCTION forbid_ledger_changes() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'ledger_entries is append-only: % is not allowed', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ledger_append_only
    BEFORE UPDATE OR DELETE ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION forbid_ledger_changes();