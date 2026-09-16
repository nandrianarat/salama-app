"""Dependances partagees par les routeurs de l'API."""

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from auth import decode_access_token
from database import get_db
from models import Personnel


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Personnel:
    try:
        payload = decode_access_token(token)
        user_id = payload.get("sub")
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalide ou expire",
        ) from error

    user = db.query(Personnel).filter(Personnel.id == user_id).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Utilisateur introuvable",
        )
    return user


def normalize_uuid(value):
    return str(value) if value is not None else None
