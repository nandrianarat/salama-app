"""Routes des consultations medicales."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_current_user, normalize_uuid, require_medical_access
from models import Consultation, Patient, Personnel
from schemas import ConsultationCreate, ConsultationOut, ConsultationSync, ConsultationUpdate

router = APIRouter(prefix="/api/v1", tags=["consultations"])


@router.get("/consultations", response_model=list[ConsultationOut])
def list_consultations(
    patient_id: UUID | None = None,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    del current_user
    query = db.query(Consultation).filter(Consultation.is_deleted == False)
    if patient_id:
        query = query.filter(Consultation.patient_id == patient_id)
    return query.order_by(Consultation.created_at.desc()).all()


@router.post("/consultations", response_model=ConsultationOut, status_code=status.HTTP_201_CREATED)
def create_consultation(
    consultation_data: ConsultationCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    patient = db.query(Patient).filter(Patient.id == consultation_data.patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient introuvable")
    consultation = Consultation(
        patient_id=normalize_uuid(consultation_data.patient_id),
        medecin_id=normalize_uuid(current_user.id),
        lieu=consultation_data.lieu,
        motif=consultation_data.motif,
        temperature=consultation_data.temperature,
        tension_arterielle=consultation_data.tension_arterielle,
        diagnostic=consultation_data.diagnostic,
        notes=consultation_data.notes,
    )
    db.add(consultation)
    db.commit()
    db.refresh(consultation)
    return consultation


@router.post("/sync/consultations", response_model=ConsultationOut)
def sync_consultation(
    consultation_data: ConsultationSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(require_medical_access),
):
    patient_id = normalize_uuid(consultation_data.patient_id)
    if not db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first():
        raise HTTPException(status_code=404, detail="Patient introuvable")
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
    elif consultation.updated_at and consultation_data.updated_at and consultation.updated_at > consultation_data.updated_at:
        return consultation
    else:
        for field, value in consultation_data.model_dump(exclude={"id", "updated_at", "patient_id"}).items():
            setattr(consultation, field, value)
    consultation.patient_id = patient_id
    consultation.is_deleted = consultation_data.is_deleted
    consultation.sync_status = "synced"
    consultation.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(consultation)
    return consultation


@router.put("/consultations/{consultation_id}", response_model=ConsultationOut)
def update_consultation(consultation_id: UUID, consultation_data: ConsultationUpdate, db: Session = Depends(get_db), current_user: Personnel = Depends(require_medical_access)):
    del current_user
    consultation = db.query(Consultation).filter(Consultation.id == consultation_id, Consultation.is_deleted == False).first()
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation introuvable")
    for field, value in consultation_data.model_dump(exclude_unset=True).items():
        setattr(consultation, field, value)
    consultation.updated_at = datetime.utcnow()
    consultation.sync_status = "updated"
    db.commit()
    db.refresh(consultation)
    return consultation


@router.delete("/consultations/{consultation_id}")
def delete_consultation(consultation_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(require_medical_access)):
    del current_user
    consultation = db.query(Consultation).filter(Consultation.id == consultation_id, Consultation.is_deleted == False).first()
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation introuvable")
    consultation.is_deleted = True
    consultation.sync_status = "deleted"
    consultation.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Consultation supprimée avec succès"}
