"""Routes des dossiers patients."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_current_user, normalize_uuid
from models import Patient, Personnel
from schemas import PatientCreate, PatientOut, PatientSync, PatientUpdate

router = APIRouter(prefix="/api/v1", tags=["patients"])


@router.get("/patients", response_model=list[PatientOut])
def list_patients(
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
    q: str | None = Query(default=None, description="Recherche par nom, prénom ou numéro"),
):
    del current_user
    query = db.query(Patient).filter(Patient.is_deleted == False)
    if q:
        search = f"%{q}%"
        query = query.filter(
            (Patient.nom.ilike(search))
            | (Patient.prenom.ilike(search))
            | (Patient.telephone.ilike(search))
        )
    return query.order_by(Patient.created_at.desc()).all()


@router.get("/patients/{patient_id}", response_model=PatientOut)
def get_patient(
    patient_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    return patient


@router.post("/patients", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
def create_patient(
    patient_data: PatientCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    payload = patient_data.model_dump()
    if payload.get("id") is not None:
        payload["id"] = normalize_uuid(payload["id"])
    patient = Patient(**payload)
    db.add(patient)
    db.commit()
    db.refresh(patient)
    return patient


@router.post("/sync/patients", response_model=PatientOut)
def sync_patient(
    patient_data: PatientSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    patient_id = normalize_uuid(patient_data.id)
    patient = db.query(Patient).filter(Patient.id == patient_id).first()
    values = patient_data.model_dump(exclude={"id", "updated_at"})
    if patient is None:
        patient = Patient(id=patient_id, **values)
        db.add(patient)
    else:
        if patient.updated_at and patient_data.updated_at and patient.updated_at > patient_data.updated_at:
            return patient
        for field, value in values.items():
            setattr(patient, field, value)
    patient.sync_status = "synced"
    patient.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(patient)
    return patient


@router.put("/patients/{patient_id}", response_model=PatientOut)
def update_patient(
    patient_id: UUID,
    patient_data: PatientUpdate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    for field, value in patient_data.model_dump(exclude_unset=True).items():
        setattr(patient, field, value)
    patient.updated_at = datetime.utcnow()
    patient.sync_status = "updated"
    db.commit()
    db.refresh(patient)
    return patient


@router.delete("/patients/{patient_id}")
def delete_patient(
    patient_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    patient.is_deleted = True
    patient.sync_status = "deleted"
    patient.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Patient supprimé avec succès"}
