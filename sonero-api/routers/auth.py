import hashlib
import uuid
import httpx
from collections import defaultdict
from time import time
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from passlib.context import CryptContext
from database import get_db
from models import User

router = APIRouter()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# ── Schemas ───────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    name: str
    email: str
    password: str

class LoginRequest(BaseModel):
    email: str
    password: str

class GoogleLoginRequest(BaseModel):
    id_token: str

# ── Rate Limiting ─────────────────────────────────────────────────────────────

_login_attempts: dict[str, list[float]] = defaultdict(list)

def _check_rate_limit(ip: str, max_attempts: int = 5, window: int = 60):
    """Blocks if there are more than max_attempts in the last 'window' seconds."""
    now = time()
    _login_attempts[ip] = [t for t in _login_attempts[ip] if now - t < window]
    if len(_login_attempts[ip]) >= max_attempts:
        raise HTTPException(
            status_code=429,
            detail="Demasiados intentos. Espera un minuto."
        )
    _login_attempts[ip].append(now)

# ── Helpers ───────────────────────────────────────────────────────────────────

def hash_password(password: str) -> str:
    """Hashes a new password using bcrypt."""
    return pwd_context.hash(password)

def verify_password(password: str, stored_hash: str, db: Session = None, user: User = None) -> bool:
    """
    Verifies a password against a stored hash.
    Supports both bcrypt (new) and SHA-256 (legacy) hashes.
    If a legacy SHA-256 hash is detected and valid, it is automatically
    migrated to bcrypt for future logins.
    """
    # Attempt 1: bcrypt hash (starts with $2b$)
    if stored_hash and stored_hash.startswith("$2b$"):
        return pwd_context.verify(password, stored_hash)

    # Attempt 2: legacy SHA-256 hash
    sha256_hash = hashlib.sha256(password.encode('utf-8')).hexdigest()
    if stored_hash == sha256_hash:
        # Migrate to bcrypt transparently
        if db and user:
            user.password_hash = pwd_context.hash(password)
            db.commit()
        return True

    return False

# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post(
    "/auth/register",
    summary="Register a new user",
    description="Registers a new user using email and password, storing password securely as a hash."
)
def register_user(body: RegisterRequest, db: Session = Depends(get_db)):
    # Check if user already exists
    existing = db.query(User).filter(User.email == body.email.strip().lower()).first()
    if existing:
        raise HTTPException(status_code=400, detail="El correo electrónico ya está registrado.")

    new_id = str(uuid.uuid4())
    user = User(
        id=new_id,
        name=body.name.strip(),
        email=body.email.strip().lower(),
        password_hash=hash_password(body.password),  # Uses bcrypt
        preferences='{"favorite_genres": []}'
    )
    
    db.add(user)
    db.commit()
    db.refresh(user)
    
    return {
        "message": "Registro completado con éxito.",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
    }


@router.post(
    "/auth/login",
    summary="Login with email and password",
    description="Authenticates the user using email and password."
)
def login_user(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    # Rate limiting: max 5 attempts per minute per IP
    _check_rate_limit(request.client.host if request.client else "unknown")

    user = db.query(User).filter(User.email == body.email.strip().lower()).first()
    if not user or not user.password_hash or not verify_password(body.password, user.password_hash, db=db, user=user):
        raise HTTPException(status_code=401, detail="Credenciales inválidas.")
        
    return {
        "message": "Inicio de sesión exitoso.",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
    }


@router.post(
    "/auth/google",
    summary="Login or Register with Google",
    description="Authenticates or automatically registers a user using their Google ID Token."
)
def google_auth(body: GoogleLoginRequest, db: Session = Depends(get_db)):
    id_token = body.id_token.strip()
    
    # 1. Verify token with Google API
    try:
        response = httpx.get(
            f"https://oauth2.googleapis.com/tokeninfo?id_token={id_token}",
            timeout=10.0
        )
        if response.status_code != 200:
            raise HTTPException(
                status_code=400,
                detail="Token de Google inválido o expirado."
            )
        token_info = response.json()
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=500,
            detail="Error al verificar el token de Google."
        )

    google_id = token_info.get("sub")
    email = token_info.get("email")
    name = token_info.get("name", "Usuario de Google")

    if not google_id:
        raise HTTPException(
            status_code=400,
            detail="El token de Google no contiene el identificador único del usuario (sub)."
        )

    # Look up user by Google ID (stored in id column)
    user = db.query(User).filter(User.id == google_id).first()
    
    # If not found by Google ID, search by email to link account
    if not user and email:
        user = db.query(User).filter(User.email == email.strip().lower()).first()
        if user:
            # Link Google ID to existing account
            user.id = google_id
            db.commit()
            db.refresh(user)

    if not user:
        # Register new Google User
        user = User(
            id=google_id,
            name=name.strip(),
            email=email.strip().lower() if email else None,
            preferences='{"favorite_genres": []}'
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    return {
        "message": "Autenticación de Google exitosa.",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
    }
