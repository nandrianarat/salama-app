"""Routes d'authentification HaD France."""

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from auth import create_access_token, hash_password, verify_password
from database import get_db
from dependencies import get_current_user
from models import Personnel
from schemas import RegisterRequest
from pydantic import BaseModel, Field


class ProfileUpdate(BaseModel):
    nom: str = Field(..., min_length=2)

router = APIRouter(tags=["auth"])


@router.post("/api/v1/auth/login")
@router.post("/auth/login")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    user = db.query(Personnel).filter(Personnel.login == form_data.username).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Votre identifiant est incorrect",
        )
    if not verify_password(form_data.password, user.mot_de_passe_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Votre mot de passe est incorrect",
        )

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {"id": str(user.id), "nom": user.nom, "role": user.role},
    }


@router.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    login_value = data.login.strip().lower()
    if db.query(Personnel).filter(Personnel.login == login_value).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cet identifiant est déjà utilisé",
        )

    user = Personnel(
        nom=data.nom.strip(),
        role=data.role,
        specialite="Professionnel de santé",
        login=login_value,
        mot_de_passe_hash=hash_password(data.mot_de_passe),
    )
    db.add(user)
    db.commit()
    return {"detail": "Compte créé", "login": login_value, "role": data.role}


@router.get("/auth/me")
@router.get("/api/v1/auth/me")
def read_current_user(current_user: Personnel = Depends(get_current_user)):
    return {
        "id": str(current_user.id),
        "nom": current_user.nom,
        "role": current_user.role,
        "login": current_user.login,
        "email": current_user.login,
        "specialite": current_user.specialite,
        "numero_ordre": current_user.numero_ordre,
    }


@router.put("/auth/me")
@router.put("/api/v1/auth/me")
def update_current_user(
    data: ProfileUpdate,
    current_user: Personnel = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    current_user.nom = data.nom.strip()
    db.commit()
    db.refresh(current_user)
    return {
        "id": str(current_user.id),
        "nom": current_user.nom,
        "role": current_user.role,
        "login": current_user.login,
        "email": current_user.login,
        "specialite": current_user.specialite,
        "numero_ordre": current_user.numero_ordre,
    }
