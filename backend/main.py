from datetime import date, datetime
import json
import os
import tempfile
from typing import Literal
from uuid import UUID

from fastapi import FastAPI, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from database import engine, get_db, Base, SessionLocal
from models import AuditLog, Consultation, LignePrescription, Ordonnance, Patient, Personnel, RendezVous
from auth import hash_password, verify_password, create_access_token, decode_access_token
from dependencies import (
    get_current_user,
    normalize_uuid,
    require_admin,
    require_doctor,
    require_doctor_or_patient,
    require_clinical_or_patient,
    require_medical_access,
    require_patient_records_access,
    require_patient,
    require_schedule_access,
    require_schedule_or_patient,
)
from routers.auth import router as auth_router
from schemas import (
    AdminMedicalAuditRequest,
    AdminPasswordReset,
    AdminUserCreate,
    AdminUserUpdate,
    PatientSelfUpdate,
    PersonnelOut,
)

# Crée les tables si elles n'existent pas déjà (utile en développement)
Base.metadata.create_all(bind=engine)


def ensure_schema_updates():
    inspector = inspect(engine)
    with engine.begin() as connection:
        tables = inspector.get_table_names()
        if "consultation" in tables:
            columns = {column["name"] for column in inspector.get_columns("consultation")}
        else:
            columns = set()
        if "consultation" in tables and "lieu" not in columns:
            connection.execute(text(
                "ALTER TABLE consultation ADD COLUMN lieu VARCHAR(20) "
                "NOT NULL DEFAULT 'Cabinet'"
            ))
        if "consultation" in tables and "temperature" not in columns:
            connection.execute(text(
                "ALTER TABLE consultation ADD COLUMN temperature VARCHAR(20)"
            ))
        if "consultation" in tables and "tension_arterielle" not in columns:
            connection.execute(text(
                "ALTER TABLE consultation ADD COLUMN tension_arterielle VARCHAR(20)"
            ))
        if "consultation" in tables and "statut" not in columns:
            connection.execute(text(
                "ALTER TABLE consultation ADD COLUMN statut VARCHAR(20) NOT NULL DEFAULT 'en_cours'"
            ))
        if "patient" in tables:
            patient_columns = {column["name"] for column in inspector.get_columns("patient")}
            if "medecin_id" not in patient_columns:
                connection.execute(text(
                    "ALTER TABLE patient ADD COLUMN medecin_id VARCHAR(36)"
                ))
        if "personnel" in tables:
            personnel_columns = {column["name"] for column in inspector.get_columns("personnel")}
            if "patient_id" not in personnel_columns:
                connection.execute(text(
                    "ALTER TABLE personnel ADD COLUMN patient_id VARCHAR(36)"
                ))
            if engine.url.get_backend_name() == "postgresql":
                connection.execute(text(
                    "ALTER TABLE personnel DROP CONSTRAINT IF EXISTS personnel_role_check"
                ))
                connection.execute(text(
                    "ALTER TABLE personnel ADD CONSTRAINT personnel_role_check "
                    "CHECK (role IN ('admin', 'medecin', 'infirmier', 'secretaire', 'patient'))"
                ))


ensure_schema_updates()


def ensure_default_admin():
    db = SessionLocal()
    try:
        existing = db.query(Personnel).filter(Personnel.login == "admin").first()
        if existing is None:
            admin = Personnel(
                nom="Admin",
                role="admin",
                specialite="Système",
                numero_ordre="ADMIN",
                login="admin",
                mot_de_passe_hash=hash_password("admin123"),
            )
            db.add(admin)
            db.commit()
    finally:
        db.close()


ensure_default_admin()

app = FastAPI(title="Service Santé API")
app.include_router(auth_router)


@app.get("/api/v1/personnel")
@app.get("/api/v1/users")
def list_personnel(
    role: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_access),
):
    query = db.query(Personnel).filter(Personnel.is_deleted == False)
    if current_user.role.strip().lower() != "admin":
        query = query.filter(Personnel.role.in_(["medecin", "infirmier"]))
    if role:
        query = query.filter(Personnel.role == role)
    users = query.order_by(Personnel.created_at.asc()).all()
    if current_user.role.strip().lower() == "admin":
        return users
    return [
        {
            "id": user.id,
            "nom": user.nom,
            "role": user.role,
            "specialite": user.specialite,
            "numero_ordre": user.numero_ordre,
        }
        for user in users
    ]


def write_audit_log(db: Session, actor: Personnel, action: str, target_type: str, target_id=None, details=None):
    db.add(AuditLog(
        actor_id=normalize_uuid(actor.id),
        action=action,
        target_type=target_type,
        target_id=normalize_uuid(target_id),
        details=json.dumps(details, ensure_ascii=True) if details else None,
    ))


def patient_directory_payload(patient: Patient):
    return {
        "id": patient.id,
        "nom": patient.nom,
        "prenom": patient.prenom,
        "date_naissance": patient.date_naissance,
        "sexe": patient.sexe,
        "telephone": patient.telephone,
        "adresse": patient.adresse,
        "contact_urgence": patient.contact_urgence,
        "medecin_id": patient.medecin_id,
        "created_at": patient.created_at,
        "updated_at": patient.updated_at,
        "sync_status": patient.sync_status,
        "is_deleted": patient.is_deleted,
    }


@app.post("/api/v1/admin/users", response_model=PersonnelOut, status_code=status.HTTP_201_CREATED)
def create_admin_user(
    data: AdminUserCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    login_value = data.login.strip().lower()
    if db.query(Personnel).filter(Personnel.login == login_value).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Cet identifiant est déjà utilisé")
    user = Personnel(
        nom=data.nom.strip(),
        login=login_value,
        role=data.role,
        specialite=data.specialite,
        numero_ordre=data.numero_ordre,
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
    write_audit_log(db, current_user, "user.created", "personnel", user.id, {"role": user.role})
    db.commit()
    db.refresh(user)
    return user


@app.put("/api/v1/admin/users/{user_id}", response_model=PersonnelOut)
def update_admin_user(
    user_id: UUID,
    data: AdminUserUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    user = db.query(Personnel).filter(Personnel.id == user_id, Personnel.is_deleted == False).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Utilisateur introuvable")
    values = data.model_dump(exclude_unset=True)
    if "login" in values:
        values["login"] = values["login"].strip().lower()
        duplicate = db.query(Personnel).filter(Personnel.login == values["login"], Personnel.id != user_id).first()
        if duplicate:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Cet identifiant est déjà utilisé")
    if user.id == current_user.id and values.get("role") != "admin":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Impossible de retirer son propre rôle administrateur")
    for field, value in values.items():
        setattr(user, field, value.strip() if isinstance(value, str) else value)
    write_audit_log(db, current_user, "user.updated", "personnel", user.id, {"fields": list(values)})
    db.commit()
    db.refresh(user)
    return user


@app.delete("/api/v1/admin/users/{user_id}")
def deactivate_admin_user(
    user_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Impossible de désactiver son propre compte")
    user = db.query(Personnel).filter(Personnel.id == user_id, Personnel.is_deleted == False).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Utilisateur introuvable")
    user.is_deleted = True
    user.updated_at = datetime.utcnow()
    write_audit_log(db, current_user, "user.deactivated", "personnel", user.id)
    db.commit()
    return {"detail": "Utilisateur désactivé"}


@app.post("/api/v1/admin/users/{user_id}/reset-password")
def reset_admin_password(
    user_id: UUID,
    data: AdminPasswordReset,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    user = db.query(Personnel).filter(Personnel.id == user_id, Personnel.is_deleted == False).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Utilisateur introuvable")
    user.mot_de_passe_hash = hash_password(data.mot_de_passe)
    user.updated_at = datetime.utcnow()
    write_audit_log(db, current_user, "user.password_reset", "personnel", user.id)
    db.commit()
    return {"detail": "Mot de passe réinitialisé"}


@app.get("/api/v1/admin/stats")
def admin_stats(db: Session = Depends(get_db), current_user: Personnel = Depends(require_admin)):
    del current_user
    total_syncable = db.query(Consultation).count() + db.query(Ordonnance).count() + db.query(RendezVous).count()
    synced = sum([
        db.query(Consultation).filter(Consultation.sync_status == "synced").count(),
        db.query(Ordonnance).filter(Ordonnance.sync_status == "synced").count(),
        db.query(RendezVous).filter(RendezVous.sync_status == "synced").count(),
    ])
    return {
        "users": db.query(Personnel).filter(Personnel.is_deleted == False).count(),
        "patients": db.query(Patient).filter(Patient.is_deleted == False).count(),
        "consultations": db.query(Consultation).filter(Consultation.is_deleted == False).count(),
        "ordonnances": db.query(Ordonnance).filter(Ordonnance.is_deleted == False).count(),
        "rendezvous": db.query(RendezVous).filter(RendezVous.is_deleted == False).count(),
        "sync_rate": round((synced / total_syncable) * 100, 2) if total_syncable else 100,
    }


@app.get("/api/v1/admin/audit-logs")
def admin_audit_logs(db: Session = Depends(get_db), current_user: Personnel = Depends(require_admin)):
    del current_user
    logs = db.query(AuditLog).order_by(AuditLog.created_at.desc()).limit(200).all()
    return [{
        "id": log.id,
        "action": log.action,
        "target_type": log.target_type,
        "target_id": log.target_id,
        "details": json.loads(log.details) if log.details else None,
        "created_at": log.created_at,
    } for log in logs]


@app.post("/api/v1/admin/audit/consultations/{consultation_id}")
def audit_consultation_content(
    consultation_id: UUID,
    data: AdminMedicalAuditRequest,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    consultation = db.query(Consultation).filter(Consultation.id == consultation_id).first()
    if consultation is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
    write_audit_log(
        db,
        current_user,
        "medical.audit_read",
        "consultation",
        consultation.id,
        {"motif": data.motif},
    )
    db.commit()
    return {
        "id": consultation.id,
        "patient_id": consultation.patient_id,
        "medecin_id": consultation.medecin_id,
        "date": consultation.date,
        "lieu": consultation.lieu,
        "motif": consultation.motif,
        "temperature": consultation.temperature,
        "tension_arterielle": consultation.tension_arterielle,
        "diagnostic": consultation.diagnostic,
        "notes": consultation.notes,
    }


@app.post("/api/v1/admin/audit/ordonnances/{ordonnance_id}")
def audit_ordonnance_content(
    ordonnance_id: UUID,
    data: AdminMedicalAuditRequest,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_admin),
):
    ordonnance = db.query(Ordonnance).filter(Ordonnance.id == ordonnance_id).first()
    if ordonnance is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ordonnance introuvable")
    write_audit_log(
        db,
        current_user,
        "medical.audit_read",
        "ordonnance",
        ordonnance.id,
        {"motif": data.motif},
    )
    db.commit()
    return {
        "id": ordonnance.id,
        "consultation_id": ordonnance.consultation_id,
        "patient_id": ordonnance.patient_id,
        "medecin_id": ordonnance.medecin_id,
        "date_emission": ordonnance.date_emission,
        "instructions_generales": ordonnance.instructions_generales,
        "lignes": [
            {
                "id": line.id,
                "medicament": line.medicament,
                "dosage": line.dosage,
                "frequence": line.frequence,
                "duree": line.duree,
            }
            for line in ordonnance.lignes
        ],
    }


class PatientCreate(BaseModel):
    id: UUID | None = None
    nom: str = Field(..., min_length=2)
    prenom: str = Field(..., min_length=2)
    date_naissance: date | None = None
    sexe: str | None = None
    telephone: str | None = None
    adresse: str | None = None
    groupe_sanguin: str | None = None
    allergies: str | None = None
    contact_urgence: str | None = None
    login: str = Field(..., min_length=3)
    mot_de_passe: str = Field(..., min_length=6)


class PatientSync(BaseModel):
    id: UUID
    nom: str = Field(..., min_length=2)
    prenom: str = Field(..., min_length=2)
    date_naissance: date | None = None
    sexe: str | None = None
    telephone: str | None = None
    adresse: str | None = None
    groupe_sanguin: str | None = None
    allergies: str | None = None
    contact_urgence: str | None = None
    updated_at: datetime | None = None
    is_deleted: bool = False


class PatientUpdate(BaseModel):
    nom: str | None = None
    prenom: str | None = None
    date_naissance: date | None = None
    sexe: str | None = None
    telephone: str | None = None
    adresse: str | None = None
    groupe_sanguin: str | None = None
    allergies: str | None = None
    contact_urgence: str | None = None


class PatientOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    nom: str
    prenom: str
    date_naissance: date | None = None
    sexe: str | None = None
    telephone: str | None = None
    adresse: str | None = None
    groupe_sanguin: str | None = None
    allergies: str | None = None
    contact_urgence: str | None = None
    medecin_id: UUID | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool


class ConsultationCreate(BaseModel):
    patient_id: UUID
    lieu: Literal["Cabinet", "Domicile"] = "Cabinet"
    motif: str | None = None
    temperature: str | None = None
    tension_arterielle: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    statut: Literal["en_cours", "terminee"] = "en_cours"


class ConsultationUpdate(BaseModel):
    motif: str | None = None
    temperature: str | None = None
    tension_arterielle: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    statut: Literal["en_cours", "terminee"] | None = None


class ConsultationSync(BaseModel):
    id: UUID
    patient_id: UUID
    lieu: Literal["Cabinet", "Domicile"] = "Cabinet"
    motif: str | None = None
    temperature: str | None = None
    tension_arterielle: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    date: datetime | None = None
    updated_at: datetime | None = None
    is_deleted: bool = False
    statut: Literal["en_cours", "terminee"] = "en_cours"


class ConsultationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    patient_id: UUID
    medecin_id: UUID
    lieu: str = "Cabinet"
    date: datetime | None = None
    motif: str | None = None
    temperature: str | None = None
    tension_arterielle: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool
    statut: str = "en_cours"


class RendezVousCreate(BaseModel):
    patient_id: UUID
    medecin_id: UUID
    date_heure: datetime
    statut: Literal["confirme", "annule", "termine"] = "confirme"
    motif: str | None = None


class RendezVousUpdate(BaseModel):
    date_heure: datetime | None = None
    statut: Literal["confirme", "annule", "termine"] | None = None
    motif: str | None = None


class RendezVousSync(BaseModel):
    id: UUID
    patient_id: UUID
    date_heure: datetime
    statut: Literal["confirme", "annule", "termine"] = "confirme"
    motif: str | None = None
    updated_at: datetime | None = None
    is_deleted: bool = False


class RendezVousOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    patient_id: UUID
    medecin_id: UUID
    date_heure: datetime
    statut: str
    motif: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool


class LignePrescriptionCreate(BaseModel):
    medicament: str = Field(..., min_length=2)
    dosage: str | None = None
    frequence: str | None = None
    duree: str | None = None


class LignePrescriptionOut(LignePrescriptionCreate):
    model_config = ConfigDict(from_attributes=True)

    id: UUID


class OrdonnanceCreate(BaseModel):
    consultation_id: UUID
    date_emission: date | None = None
    instructions_generales: str | None = None
    lignes: list[LignePrescriptionCreate] = Field(..., min_length=1)


class OrdonnanceSync(OrdonnanceCreate):
    id: UUID
    patient_id: UUID
    updated_at: datetime | None = None
    is_deleted: bool = False


class OrdonnanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    consultation_id: UUID
    patient_id: UUID
    medecin_id: UUID
    date_emission: date
    instructions_generales: str | None = None
    lignes: list[LignePrescriptionOut] = []
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool


@app.get("/health")
def health_check():
    return {"status": "ok"}

@app.get("/api/v1/patients")
def list_patients(
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient_records_access),
    q: str | None = Query(default=None, description="Recherche par nom, prénom ou numéro"),
):
    query = db.query(Patient).filter(Patient.is_deleted == False)
    if current_user.role.strip().lower() == "patient":
        query = query.filter(Patient.id == current_user.patient_id)
    elif current_user.role.strip().lower() in {"medecin", "infirmier"}:
        query = query.filter(
            (Patient.medecin_id == normalize_uuid(current_user.id)) |
            (Patient.medecin_id.is_(None))
        )
    if q:
        search = f"%{q}%"
        query = query.filter(
            (Patient.nom.ilike(search)) |
            (Patient.prenom.ilike(search)) |
            (Patient.telephone.ilike(search))
        )
    patients = query.order_by(Patient.created_at.desc()).all()
    if current_user.role.strip().lower() == "secretaire":
        return [patient_directory_payload(patient) for patient in patients]
    return patients


@app.get("/api/v1/patients/{patient_id}", response_model=PatientOut)
def get_patient(
    patient_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient_records_access),
):
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
    ).first()
    if current_user.role.strip().lower() == "patient" and patient_id != current_user.patient_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier d'un autre patient interdit")
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    if current_user.role.strip().lower() == "secretaire":
        return patient_directory_payload(patient)
    return patient


@app.get("/api/v1/me/patient", response_model=PatientOut)
def get_my_patient(
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient),
):
    patient = db.query(Patient).filter(
        Patient.id == current_user.patient_id,
        Patient.is_deleted == False,
    ).first()
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dossier patient introuvable")
    return patient


@app.put("/api/v1/me/patient", response_model=PatientOut)
def update_my_patient(
    data: PatientSelfUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient),
):
    patient = db.query(Patient).filter(
        Patient.id == current_user.patient_id,
        Patient.is_deleted == False,
    ).first()
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dossier patient introuvable")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(patient, field, value)
    patient.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(patient)
    return patient


@app.post("/api/v1/patients", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
def create_patient(
    patient_data: PatientCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient_records_access),
):
    if current_user.role.strip().lower() == "patient":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Création de dossier interdite")
    payload = patient_data.model_dump()
    login_value = payload.pop("login").strip().lower()
    password_value = payload.pop("mot_de_passe")
    if db.query(Personnel).filter(Personnel.login == login_value).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Cet identifiant est déjà utilisé")
    if current_user.role.strip().lower() == "secretaire" and any(
        payload.get(field) for field in ("groupe_sanguin", "allergies")
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Les données médicales ne peuvent pas être saisies par une secrétaire",
        )
    if payload.get("id") is not None:
        payload["id"] = normalize_uuid(payload["id"])
    payload["medecin_id"] = (
        normalize_uuid(current_user.id)
        if current_user.role.strip().lower() in {"medecin", "infirmier"}
        else None
    )
    patient = Patient(**payload)
    db.add(patient)
    db.flush()
    db.add(Personnel(
        nom=f"{patient_data.prenom.strip()} {patient_data.nom.strip()}".strip(),
        role="patient",
        specialite="Patient",
        login=login_value,
        mot_de_passe_hash=hash_password(password_value),
        patient_id=patient.id,
        sync_status="synced",
    ))
    db.commit()
    db.refresh(patient)
    return patient


@app.post("/api/v1/sync/patients", response_model=PatientOut)
def sync_patient(
    patient_data: PatientSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient_records_access),
):
    if current_user.role.strip().lower() == "patient":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Synchronisation de dossier interdite")
    patient_id = normalize_uuid(patient_data.id)
    patient = db.query(Patient).filter(Patient.id == patient_id).first()
    values = patient_data.model_dump(exclude={"id", "updated_at"})
    if current_user.role.strip().lower() == "secretaire":
        values.pop("groupe_sanguin", None)
        values.pop("allergies", None)
    if patient is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Un compte patient doit être créé avant la synchronisation du dossier",
        )
    else:
        if (
            current_user.role.strip().lower() in {"medecin", "infirmier"}
            and patient.medecin_id not in {None, normalize_uuid(current_user.id)}
        ):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")
        server_updated = patient.updated_at
        client_updated = patient_data.updated_at
        if server_updated is not None and client_updated is not None and server_updated > client_updated:
            return patient_directory_payload(patient) if current_user.role.strip().lower() == "secretaire" else patient
        for field, value in values.items():
            setattr(patient, field, value)
    patient.sync_status = "synced"
    patient.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(patient)
    return patient_directory_payload(patient) if current_user.role.strip().lower() == "secretaire" else patient


@app.put("/api/v1/patients/{patient_id}", response_model=PatientOut)
def update_patient(
    patient_id: UUID,
    patient_data: PatientUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_patient_records_access),
):
    if current_user.role.strip().lower() == "patient":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Utilisez votre profil personnel")
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")

    values = patient_data.model_dump(exclude_unset=True)
    if current_user.role.strip().lower() == "secretaire":
        forbidden = {"groupe_sanguin", "allergies"} & values.keys()
        if forbidden:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Modification de données médicales interdite",
            )
    for field, value in values.items():
        setattr(patient, field, value)

    patient.updated_at = datetime.utcnow()
    patient.sync_status = "updated"
    db.commit()
    db.refresh(patient)
    return patient_directory_payload(patient) if current_user.role.strip().lower() == "secretaire" else patient


@app.delete("/api/v1/patients/{patient_id}")
def delete_patient(patient_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(require_medical_access)):
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
        Patient.medecin_id == normalize_uuid(current_user.id),
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")

    patient.is_deleted = True
    patient.sync_status = "deleted"
    patient.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Patient supprimé avec succès"}


@app.get("/api/v1/consultations", response_model=list[ConsultationOut])
def list_consultations(
    patient_id: UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_clinical_or_patient),
):
    query = db.query(Consultation).join(Patient).filter(Consultation.is_deleted == False)
    if current_user.role.strip().lower() == "patient":
        query = query.filter(Consultation.patient_id == current_user.patient_id)
    else:
        query = query.filter(Patient.medecin_id == normalize_uuid(current_user.id))
    if patient_id:
        query = query.filter(Consultation.patient_id == patient_id)
    return query.order_by(Consultation.created_at.desc()).all()


@app.post("/api/v1/consultations", response_model=ConsultationOut, status_code=status.HTTP_201_CREATED)
def create_consultation(
    consultation_data: ConsultationCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    patient = db.query(Patient).filter(Patient.id == consultation_data.patient_id, Patient.is_deleted == False).first()
    if patient is not None and patient.medecin_id != normalize_uuid(current_user.id):
        patient = None
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")

    consultation = Consultation(
        patient_id=normalize_uuid(consultation_data.patient_id),
        medecin_id=normalize_uuid(current_user.id),
        lieu=consultation_data.lieu,
        motif=consultation_data.motif,
        temperature=consultation_data.temperature,
        tension_arterielle=consultation_data.tension_arterielle,
        diagnostic=consultation_data.diagnostic,
        notes=consultation_data.notes,
        statut=consultation_data.statut,
    )
    db.add(consultation)
    db.commit()
    db.refresh(consultation)
    return consultation


@app.post("/api/v1/sync/consultations", response_model=ConsultationOut)
def sync_consultation(
    consultation_data: ConsultationSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    patient_id = normalize_uuid(consultation_data.patient_id)
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
        Patient.medecin_id == normalize_uuid(current_user.id),
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    consultation = db.query(Consultation).filter(Consultation.id == normalize_uuid(consultation_data.id)).first()
    if consultation is None:
        consultation = Consultation(
            id=normalize_uuid(consultation_data.id),
            patient_id=patient_id,
            medecin_id=normalize_uuid(current_user.id),
            date=consultation_data.date,
            lieu=consultation_data.lieu,
            motif=consultation_data.motif,
            temperature=consultation_data.temperature,
            tension_arterielle=consultation_data.tension_arterielle,
            diagnostic=consultation_data.diagnostic,
            notes=consultation_data.notes,
        )
        db.add(consultation)
    else:
        if consultation.statut == "terminee":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Consultation clôturée et non modifiable")
        if consultation.updated_at and consultation_data.updated_at and consultation.updated_at > consultation_data.updated_at:
            return consultation
        for field, value in consultation_data.model_dump(exclude={"id", "updated_at", "patient_id"}).items():
            setattr(consultation, field, value)
    consultation.patient_id = patient_id
    consultation.lieu = consultation_data.lieu
    consultation.statut = consultation_data.statut
    consultation.is_deleted = consultation_data.is_deleted
    consultation.sync_status = "synced"
    consultation.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(consultation)
    return consultation


@app.put("/api/v1/consultations/{consultation_id}", response_model=ConsultationOut)
def update_consultation(
    consultation_id: UUID,
    consultation_data: ConsultationUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
    if consultation.patient.medecin_id != normalize_uuid(current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")
    if consultation.statut == "terminee":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Consultation clôturée et non modifiable")

    for field, value in consultation_data.model_dump(exclude_unset=True).items():
        setattr(consultation, field, value)
    consultation.updated_at = datetime.utcnow()
    consultation.sync_status = "updated"
    db.commit()
    db.refresh(consultation)
    return consultation


@app.delete("/api/v1/consultations/{consultation_id}")
def delete_consultation(
    consultation_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
    if consultation.patient.medecin_id != normalize_uuid(current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")
    if consultation.statut == "terminee":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Consultation clôturée et non supprimable")

    consultation.is_deleted = True
    consultation.sync_status = "deleted"
    consultation.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Consultation supprimée avec succès"}


@app.get("/api/v1/rendezvous", response_model=list[RendezVousOut])
def list_rendezvous(
    patient_id: UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_or_patient),
):
    query = db.query(RendezVous).filter(RendezVous.is_deleted == False)
    if current_user.role.strip().lower() == "patient":
        query = query.filter(RendezVous.patient_id == current_user.patient_id)
    if patient_id:
        query = query.filter(RendezVous.patient_id == patient_id)
    return query.order_by(RendezVous.date_heure.asc()).all()


@app.post("/api/v1/rendezvous", response_model=RendezVousOut, status_code=status.HTTP_201_CREATED)
def create_rendezvous(
    rendezvous_data: RendezVousCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_or_patient),
):
    if (
        current_user.role.strip().lower() == "patient"
        and normalize_uuid(rendezvous_data.patient_id) != normalize_uuid(current_user.patient_id)
    ):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Rendez-vous d'un autre patient interdit")
    patient = db.query(Patient).filter(
        Patient.id == rendezvous_data.patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    doctor = db.query(Personnel).filter(
        Personnel.id == rendezvous_data.medecin_id,
        Personnel.role.in_(["medecin", "infirmier"]),
        Personnel.is_deleted == False,
    ).first()
    if not doctor:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Médecin introuvable")

    rendezvous = RendezVous(
        patient_id=normalize_uuid(rendezvous_data.patient_id),
        medecin_id=normalize_uuid(doctor.id),
        date_heure=rendezvous_data.date_heure,
        statut=rendezvous_data.statut,
        motif=rendezvous_data.motif,
    )
    db.add(rendezvous)
    db.commit()
    db.refresh(rendezvous)
    return rendezvous


@app.post("/api/v1/sync/rendezvous", response_model=RendezVousOut)
def sync_rendezvous(
    rendezvous_data: RendezVousSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_or_patient),
):
    if (
        current_user.role.strip().lower() == "patient"
        and normalize_uuid(rendezvous_data.patient_id) != normalize_uuid(current_user.patient_id)
    ):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Rendez-vous d'un autre patient interdit")
    patient_id = normalize_uuid(rendezvous_data.patient_id)
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    rendezvous = db.query(RendezVous).filter(RendezVous.id == normalize_uuid(rendezvous_data.id)).first()
    if rendezvous is None:
        rendezvous = RendezVous(id=normalize_uuid(rendezvous_data.id), medecin_id=normalize_uuid(current_user.id))
        db.add(rendezvous)
    elif rendezvous.updated_at and rendezvous_data.updated_at and rendezvous.updated_at > rendezvous_data.updated_at:
        return rendezvous
    rendezvous.patient_id = patient_id
    rendezvous.date_heure = rendezvous_data.date_heure
    rendezvous.statut = rendezvous_data.statut
    rendezvous.motif = rendezvous_data.motif
    rendezvous.is_deleted = rendezvous_data.is_deleted
    rendezvous.sync_status = "synced"
    rendezvous.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(rendezvous)
    return rendezvous


@app.put("/api/v1/rendezvous/{rendezvous_id}", response_model=RendezVousOut)
def update_rendezvous(
    rendezvous_id: UUID,
    rendezvous_data: RendezVousUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_or_patient),
):
    rendezvous = db.query(RendezVous).filter(
        RendezVous.id == rendezvous_id,
        RendezVous.is_deleted == False,
    ).first()
    if not rendezvous:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rendez-vous introuvable")
    if current_user.role.strip().lower() == "patient" and rendezvous.patient_id != current_user.patient_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Rendez-vous d'un autre patient interdit")

    for field, value in rendezvous_data.model_dump(exclude_unset=True).items():
        setattr(rendezvous, field, value)
    rendezvous.updated_at = datetime.utcnow()
    rendezvous.sync_status = "updated"
    db.commit()
    db.refresh(rendezvous)
    return rendezvous


@app.delete("/api/v1/rendezvous/{rendezvous_id}")
def delete_rendezvous(
    rendezvous_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_schedule_or_patient),
):
    rendezvous = db.query(RendezVous).filter(
        RendezVous.id == rendezvous_id,
        RendezVous.is_deleted == False,
    ).first()
    if not rendezvous:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rendez-vous introuvable")
    if current_user.role.strip().lower() == "patient" and rendezvous.patient_id != current_user.patient_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Rendez-vous d'un autre patient interdit")

    rendezvous.is_deleted = True
    rendezvous.sync_status = "deleted"
    rendezvous.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Rendez-vous supprimé avec succès"}


@app.get("/api/v1/ordonnances", response_model=list[OrdonnanceOut])
def list_ordonnances(
    patient_id: UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_doctor_or_patient),
):
    query = db.query(Ordonnance).join(Patient).filter(Ordonnance.is_deleted == False)
    if current_user.role.strip().lower() == "patient":
        query = query.filter(Ordonnance.patient_id == current_user.patient_id)
    else:
        query = query.filter(Patient.medecin_id == normalize_uuid(current_user.id))
    if patient_id:
        query = query.filter(Ordonnance.patient_id == patient_id)
    return query.order_by(Ordonnance.date_emission.desc()).all()


@app.post("/api/v1/ordonnances", response_model=OrdonnanceOut, status_code=status.HTTP_201_CREATED)
def create_ordonnance(
    ordonnance_data: OrdonnanceCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_doctor),
):
    consultation = db.query(Consultation).filter(
        Consultation.id == ordonnance_data.consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")

    patient = db.query(Patient).filter(
        Patient.id == consultation.patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    if patient.medecin_id != normalize_uuid(current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")

    ordonnance = Ordonnance(
        consultation_id=normalize_uuid(consultation.id),
        patient_id=normalize_uuid(consultation.patient_id),
        medecin_id=normalize_uuid(current_user.id),
        date_emission=ordonnance_data.date_emission or date.today(),
        instructions_generales=ordonnance_data.instructions_generales,
        lignes=[LignePrescription(**ligne.model_dump()) for ligne in ordonnance_data.lignes],
    )
    db.add(ordonnance)
    db.commit()
    db.refresh(ordonnance)
    return ordonnance


@app.post("/api/v1/sync/ordonnances", response_model=OrdonnanceOut)
def sync_ordonnance(
    ordonnance_data: OrdonnanceSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_doctor),
):
    consultation_id = normalize_uuid(ordonnance_data.consultation_id)
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
    if consultation.patient.medecin_id != normalize_uuid(current_user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")
    ordonnance = db.query(Ordonnance).filter(Ordonnance.id == normalize_uuid(ordonnance_data.id)).first()
    if ordonnance is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Ordonnance déjà créée et non modifiable")
    ordonnance = Ordonnance(id=normalize_uuid(ordonnance_data.id), medecin_id=normalize_uuid(current_user.id))
    db.add(ordonnance)
    ordonnance.consultation_id = consultation_id
    ordonnance.patient_id = normalize_uuid(consultation.patient_id)
    ordonnance.date_emission = ordonnance_data.date_emission or date.today()
    ordonnance.instructions_generales = ordonnance_data.instructions_generales
    ordonnance.lignes = [LignePrescription(**ligne.model_dump()) for ligne in ordonnance_data.lignes]
    ordonnance.is_deleted = ordonnance_data.is_deleted
    ordonnance.sync_status = "synced"
    ordonnance.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(ordonnance)
    return ordonnance


@app.get("/api/v1/ordonnances/{ordonnance_id}/pdf")
def ordonnance_pdf(
    ordonnance_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_doctor_or_patient),
):
    ordonnance = db.query(Ordonnance).filter(
        Ordonnance.id == ordonnance_id,
        Ordonnance.is_deleted == False,
    ).first()
    if not ordonnance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ordonnance introuvable")
    patient = db.query(Patient).filter(Patient.id == ordonnance.patient_id).first()
    allowed = patient is not None and (
        (current_user.role.strip().lower() == "patient" and patient.id == current_user.patient_id)
        or (current_user.role.strip().lower() == "medecin" and patient.medecin_id == normalize_uuid(current_user.id))
    )
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Dossier patient non autorisé")

    patient = db.query(Patient).filter(Patient.id == ordonnance.patient_id).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")

    output_path = os.path.join(tempfile.gettempdir(), f"ordonnance-{ordonnance.id}.pdf")
    document = canvas.Canvas(output_path, pagesize=A4)
    width, height = A4
    document.setTitle("Ordonnance médicale Salama")
    document.setFont("Helvetica-Bold", 18)
    document.drawString(50, height - 60, "Salama - Ordonnance médicale")
    document.setFont("Helvetica", 11)
    document.drawString(50, height - 95, f"Patient : {patient.prenom} {patient.nom}")
    document.drawString(50, height - 115, f"Date : {ordonnance.date_emission}")
    document.drawString(50, height - 135, f"Soignant : {current_user.nom}")
    y = height - 180
    document.setFont("Helvetica-Bold", 12)
    document.drawString(50, y, "Prescription")
    document.setFont("Helvetica", 11)
    for line in ordonnance.lignes:
        y -= 22
        details = " - ".join(filter(None, [line.medicament, line.dosage, line.frequence, line.duree]))
        document.drawString(65, y, f"- {details}")
    if ordonnance.instructions_generales:
        y -= 35
        document.setFont("Helvetica-Bold", 11)
        document.drawString(50, y, "Instructions")
        document.setFont("Helvetica", 11)
        y -= 20
        document.drawString(65, y, ordonnance.instructions_generales[:110])
    document.save()
    return FileResponse(output_path, media_type="application/pdf", filename=f"ordonnance-{ordonnance.id}.pdf")
