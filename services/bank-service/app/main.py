from fastapi import FastAPI

app=FastAPI(title="Bank Service", description="Bank Service API", version="1.0.0")

@app.get("/health", tags=["Health"])
def health():
    return {"status": "ok"}