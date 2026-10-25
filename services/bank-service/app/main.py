from contextlib import asynccontextmanager
from decimal import Decimal

import psycopg
from fastapi import FastAPI, HTTPException
from psycopg.errors import UniqueViolation
from psycopg_pool import PoolTimeout
from pydantic import BaseModel, Field

from app.db import pool


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()
    yield
    pool.close()


app = FastAPI(title="bank-service", lifespan=lifespan)


class DebitRequest(BaseModel):
    txn_id: str = Field(min_length=1, max_length=64)
    rrn: str = Field(pattern=r"^[0-9]{12}$")
    account_number: str = Field(min_length=1)
    amount: Decimal = Field(gt=0, max_digits=14, decimal_places=2)


def _existing_debit(conn, txn_id: str):
    return conn.execute(
        "SELECT account_number, amount, rrn, balance_after "
        "FROM ledger_entries WHERE txn_id = %s AND entry_type = 'DEBIT'",
        (txn_id,),
    ).fetchone()


def _replay(existing, req: DebitRequest):
    """Same txn_id seen before: return the original result, never debit again."""
    account_number, amount, rrn, balance_after = existing
    if account_number != req.account_number or amount != req.amount or rrn != req.rrn:
        # Same id, different request: a client bug. Refuse loudly.
        raise HTTPException(409, detail={"code": "TXN_ID_REUSED_WITH_DIFFERENT_DATA"})
    return {
        "status": "SUCCESS",
        "txn_id": req.txn_id,
        "rrn": rrn,
        "account_number": account_number,
        "amount": str(amount),
        "balance_after": str(balance_after),
        "idempotent_replay": True,
    }


@app.get("/health")
def health():
    """Liveness: is the process alive? Never touches the database."""
    return {"status": "ok"}


@app.get("/health/db")
def health_db():
    """Readiness: can we reach the database right now?"""
    try:
        with pool.connection(timeout=2) as conn:
            conn.execute("SELECT 1").fetchone()
    except Exception:
        raise HTTPException(status_code=503, detail="database unavailable")
    return {"status": "ok"}


@app.post("/debit")
def debit(req: DebitRequest):
    try:
        with pool.connection(timeout=5) as conn:
            with conn.transaction():  # everything below commits together or not at all
                # 1. Lock the account row. Concurrent debits on it now queue up.
                row = conn.execute(
                    "SELECT balance FROM accounts WHERE account_number = %s FOR UPDATE",
                    (req.account_number,),
                ).fetchone()
                if row is None:
                    raise HTTPException(404, detail={"code": "UNKNOWN_ACCOUNT"})

                # 2. Idempotency: have we already applied this debit?
                existing = _existing_debit(conn, req.txn_id)
                if existing:
                    return _replay(existing, req)

                # 3. Business rule: enough money?
                balance = row[0]
                if balance < req.amount:
                    raise HTTPException(422, detail={"code": "INSUFFICIENT_FUNDS"})

                # 4. Change the balance and write the ledger row, in the same transaction.
                new_balance = balance - req.amount
                conn.execute(
                    "UPDATE accounts SET balance = %s WHERE account_number = %s",
                    (new_balance, req.account_number),
                )
                conn.execute(
                    "INSERT INTO ledger_entries "
                    "(txn_id, rrn, account_number, entry_type, amount, balance_after) "
                    "VALUES (%s, %s, %s, 'DEBIT', %s, %s)",
                    (req.txn_id, req.rrn, req.account_number, req.amount, new_balance),
                )
    except UniqueViolation:
        # Safety net: the database's unique constraint caught a duplicate we missed.
        with pool.connection(timeout=5) as conn:
            existing = _existing_debit(conn, req.txn_id)
        return _replay(existing, req)
    except (PoolTimeout, psycopg.OperationalError):
        # Technical failure: we don't know the outcome, the caller may retry with the SAME txn_id.
        raise HTTPException(503, detail={"code": "BANK_UNAVAILABLE"})

    return {
        "status": "SUCCESS",
        "txn_id": req.txn_id,
        "rrn": req.rrn,
        "account_number": req.account_number,
        "amount": str(req.amount),
        "balance_after": str(new_balance),
        "idempotent_replay": False,
    }