"""Routes du planning et des rendez-vous."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_current_user, normalize_uuid
from models import Patient, Personnel, RendezVous
from schemas import RendezVousCreate, RendezVousOut, RendezVousSync, RendezVousUpdate

router = APIRouter(prefix="/api/v1", tags=["rendezvous"])


@router.get("/rendezvous", response_model=list[RendezVousOut])
def list_rendezvous(patient_id: UUID | None = None, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    query = db.query(RendezVous).filter(RendezVous.is_deleted == False)
    if patient_id:
        query = query.filter(RendezVous.patient_id == patient_id)
    return query.order_by(RendezVous.date_heure.asc()).all()


@router.post("/rendezvous", response_model=RendezVousOut, status_code=status.HTTP_201_CREATED)
def create_rendezvous(rendezvous_data: RendezVousCreate, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    if not db.query(Patient).filter(Patient.id == rendezvous_data.patient_id, Patient.is_deleted == False).first():
        raise HTTPException(status_code=404, detail="Patient introuvable")
    rendezvous = RendezVous(
        patient_id=normalize_uuid(rendezvous_data.patient_id),
        medecin_id=normalize_uuid(current_user.id),
        date_heure=rendezvous_data.date_heure,
        statut=rendezvous_data.statut,
        motif=rendezvous_data.motif,
    )
    db.add(rendezvous)
    db.commit()
    db.refresh(rendezvous)
    return rendezvous


@router.post("/sync/rendezvous", response_model=RendezVousOut)
def sync_rendezvous(rendezvous_data: RendezVousSync, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    patient_id = normalize_uuid(rendezvous_data.patient_id)
    if not db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first():
        raise HTTPException(status_code=404, detail="Patient introuvable")
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


@router.put("/rendezvous/{rendezvous_id}", response_model=RendezVousOut)
def update_rendezvous(rendezvous_id: UUID, rendezvous_data: RendezVousUpdate, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    rendezvous = db.query(RendezVous).filter(RendezVous.id == rendezvous_id, RendezVous.is_deleted == False).first()
    if not rendezvous:
        raise HTTPException(status_code=404, detail="Rendez-vous introuvable")
    for field, value in rendezvous_data.model_dump(exclude_unset=True).items():
        setattr(rendezvous, field, value)
    rendezvous.updated_at = datetime.utcnow()
    rendezvous.sync_status = "updated"
    db.commit()
    db.refresh(rendezvous)
    return rendezvous


@router.delete("/rendezvous/{rendezvous_id}")
def delete_rendezvous(rendezvous_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    rendezvous = db.query(RendezVous).filter(RendezVous.id == rendezvous_id, RendezVous.is_deleted == False).first()
    if not rendezvous:
        raise HTTPException(status_code=404, detail="Rendez-vous introuvable")
    rendezvous.is_deleted = True
    rendezvous.sync_status = "deleted"
    rendezvous.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Rendez-vous supprimé avec succès"}
