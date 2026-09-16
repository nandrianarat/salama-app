from datetime import datetime, timedelta, timezone
import os

from dotenv import load_dotenv
from jose import jwt
from passlib.context import CryptContext

load_dotenv()
SECRET_KEY = os.getenv("SECRET_KEY", "salama-dev-secret-key")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # Le token reste valide 24h

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    """Transforme un mot de passe en clair en une empreinte sécurisée (hash)."""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Vérifie qu'un mot de passe en clair correspond bien au hash stocké."""
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(data: dict) -> str:
    """Crée un token JWT signé, contenant les infos passées en paramètre."""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    """Décode un token JWT et lève une erreur s'il est invalide ou expiré."""
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
