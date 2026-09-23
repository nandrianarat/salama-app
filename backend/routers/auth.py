"""Routes d'authentification HaD France."""

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from auth import create_access_token, hash_password, verify_password
from database import get_db
from dependencies import get_current_user
from models import AuditLog, Patient, Personnel
from schemas import PasswordUpdate, ProfileUpdate, RegisterRequest

router = APIRouter(tags=["auth"])


@router.post("/api/v1/auth/login")
@router.post("/auth/login")
def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db),
):
    login_value = form_data.username.strip().lower()
    user = db.query(Personnel).filter(Personnel.login == login_value).first()
    if not user or user.is_deleted:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Votre identifiant est incorrect",
        )
    if not verify_password(form_data.password, user.mot_de_passe_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Votre mot de passe est incorrect",
        )

    db.add(AuditLog(
        actor_id=str(user.id),
        action="auth.login",
        target_type="personnel",
        target_id=str(user.id),
    ))
    db.commit()

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": str(user.id),
            "nom": user.nom,
            "role": user.role,
            "patient_id": str(user.patient_id) if user.patient_id else None,
        },
    }


@router.post("/api/v1/auth/register", status_code=status.HTTP_201_CREATED)
def register(data: RegisterRequest, db: Session = Depends(get_db)):
    if data.role == "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="La création d'un administrateur est réservée à un administrateur connecté",
        )
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
    db.flush()
    if data.role == "patient":
        patient = Patient(
            nom=data.nom.strip(),
            prenom=data.nom.strip(),
            sync_status="synced",
        )
        db.add(patient)
        db.flush()
        user.patient_id = patient.id
    db.commit()
    return {"detail": "Compte créé", "login": login_value, "role": data.role}


@router.get("/auth/me")
@router.get("/api/v1/auth/me")
def read_current_user(
    current_user: Personnel = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    patient = None
    if current_user.patient_id:
        patient = db.query(Patient).filter(Patient.id == current_user.patient_id).first()
    return {
        "id": str(current_user.id),
        "nom": current_user.nom,
        "role": current_user.role,
        "login": current_user.login,
        "email": current_user.login,
        "specialite": current_user.specialite,
        "numero_ordre": current_user.numero_ordre,
        "patient_id": str(current_user.patient_id) if current_user.patient_id else None,
        "date_naissance": patient.date_naissance if patient else None,
        "groupe_sanguin": patient.groupe_sanguin if patient else None,
        "allergies": patient.allergies if patient else None,
        "telephone": patient.telephone if patient else None,
        "adresse": patient.adresse if patient else None,
        "contact_urgence": patient.contact_urgence if patient else None,
    }


@router.put("/auth/me")
@router.put("/api/v1/auth/me")
def update_current_user(
    data: ProfileUpdate,
    current_user: Personnel = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.role.strip().lower() == "patient":
        if any(
            value is not None
            for value in (data.specialite, data.numero_ordre)
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Un patient ne peut pas modifier des informations professionnelles",
            )
    login_value = data.login.strip().lower()
    duplicate = db.query(Personnel).filter(
        Personnel.login == login_value,
        Personnel.id != current_user.id,
    ).first()
    if duplicate:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Cet identifiant est déjà utilisé")
    current_user.nom = data.nom.strip()
    current_user.login = login_value
    current_user.specialite = data.specialite
    current_user.numero_ordre = data.numero_ordre
    if current_user.patient_id:
        patient = db.query(Patient).filter(Patient.id == current_user.patient_id).first()
        if patient:
            patient.date_naissance = data.date_naissance
            patient.telephone = data.telephone
            patient.adresse = data.adresse
            patient.contact_urgence = data.contact_urgence
            patient.groupe_sanguin = data.groupe_sanguin
            patient.allergies = data.allergies
    db.add(AuditLog(
        actor_id=str(current_user.id),
        action="profile.updated",
        target_type="personnel",
        target_id=str(current_user.id),
    ))
    db.commit()
    db.refresh(current_user)
    return read_current_user(current_user=current_user, db=db)


@router.put("/auth/password")
@router.put("/api/v1/auth/password")
def update_password(
    data: PasswordUpdate,
    current_user: Personnel = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(data.ancien_mot_de_passe, current_user.mot_de_passe_hash):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Ancien mot de passe incorrect")
    current_user.mot_de_passe_hash = hash_password(data.nouveau_mot_de_passe)
    db.add(AuditLog(
        actor_id=str(current_user.id),
        action="auth.password_changed",
        target_type="personnel",
        target_id=str(current_user.id),
    ))
    db.commit()
    return {"detail": "Mot de passe modifié"}
