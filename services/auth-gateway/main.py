import os
import time
import jwt
import httpx
from fastapi import FastAPI, HTTPException, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="CloudPulse Enterprise API Gateway & Auth Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:8080"],
    allow_methods=["*"],
    allow_headers=["*"],
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

JWT_SECRET = os.getenv("JWT_SECRET", "enterprise-super-secret-jwt-key")
JWT_ALGORITHM = "HS256"
CATALOG_SERVICE_URL = os.getenv("CATALOG_SERVICE_URL", "http://catalog-service:8081")
ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://order-service:8082")

class LoginRequest(BaseModel):
    username: str
    password: str

class OrderRequest(BaseModel):
    product_id: str
    quantity: int
    amount: float

def verify_jwt(authorization: str = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")
    token = authorization.split(" ")[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

@app.get("/healthz")
async def health_check():
    return {"status": "healthy", "service": "auth-gateway", "timestamp": int(time.time())}

@app.post("/api/auth/login")
async def login(req: LoginRequest):
    if req.username == "admin" and req.password == "cloudpulse2026":
        payload = {
            "sub": req.username,
            "role": "enterprise_admin",
            "exp": int(time.time()) + 3600
        }
        token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
        return {"access_token": token, "token_type": "Bearer", "expires_in": 3600}
    raise HTTPException(status_code=401, detail="Invalid credentials")

@app.get("/api/catalog")
async def get_catalog():
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.get(f"{CATALOG_SERVICE_URL}/products")
        return resp.json()

@app.post("/api/orders")
async def create_order(order: OrderRequest, authorization: str = Header(None)):
    user = verify_jwt(authorization)
    async with httpx.AsyncClient(timeout=5.0) as client:
        payload = {
            "user": user["sub"],
            "product_id": order.product_id,
            "quantity": order.quantity,
            "amount": order.amount
        }
        resp = await client.post(f"{ORDER_SERVICE_URL}/orders", json=payload)
        return resp.json()

@app.get("/api/orders")
async def list_orders():
    async with httpx.AsyncClient(timeout=5.0) as client:
        resp = await client.get(f"{ORDER_SERVICE_URL}/orders")
        return resp.json()
