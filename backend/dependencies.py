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

    user = db.query(Personnel).filter(
        Personnel.id == user_id,
        Personnel.is_deleted == False,
    ).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Utilisateur introuvable",
        )
    return user


def require_medical_access(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() not in {"medecin", "infirmier"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès réservé au personnel soignant",
        )
    return current_user


def require_doctor(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() != "medecin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cette action est réservée au médecin",
        )
    return current_user


def require_patient_records_access(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() not in {
        "medecin",
        "infirmier",
        "secretaire",
        "patient",
    }:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès réservé à la gestion des dossiers patients",
        )
    return current_user


def require_schedule_access(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() not in {
        "admin",
        "medecin",
        "infirmier",
        "secretaire",
        "patient",
    }:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès réservé à la gestion du planning",
        )
    return current_user


def require_schedule_or_patient(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    role = current_user.role.strip().lower()
    if role == "patient" and current_user.patient_id is not None:
        return current_user
    if role in {"admin", "medecin", "infirmier", "secretaire"}:
        return current_user
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Accès au planning interdit")


def require_patient(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() != "patient" or current_user.patient_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Accès réservé au dossier patient personnel",
        )
    return current_user


def require_clinical_or_patient(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    role = current_user.role.strip().lower()
    if role not in {"medecin", "infirmier", "patient"}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Accès clinique interdit")
    if role == "patient" and current_user.patient_id is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non lié")
    return current_user


def require_doctor_or_patient(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    role = current_user.role.strip().lower()
    if role == "patient" and current_user.patient_id is not None:
        return current_user
    if role == "medecin":
        return current_user
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Accès réservé au médecin ou au patient concerné")


def require_admin(
    current_user: Personnel = Depends(get_current_user),
) -> Personnel:
    if current_user.role.strip().lower() != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Réservé à l'administrateur",
        )
    return current_user


def normalize_uuid(value):
    return str(value) if value is not None else None
