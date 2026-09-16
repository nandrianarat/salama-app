"""Routes des ordonnances et generation PDF."""

import os
import tempfile
from datetime import date, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from sqlalchemy.orm import Session

from database import get_db
from dependencies import get_current_user, normalize_uuid
from models import Consultation, LignePrescription, Ordonnance, Patient, Personnel
from schemas import OrdonnanceCreate, OrdonnanceOut, OrdonnanceSync

router = APIRouter(prefix="/api/v1", tags=["ordonnances"])


@router.get("/ordonnances", response_model=list[OrdonnanceOut])
def list_ordonnances(patient_id: UUID | None = None, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    query = db.query(Ordonnance).filter(Ordonnance.is_deleted == False)
    if patient_id:
        query = query.filter(Ordonnance.patient_id == patient_id)
    return query.order_by(Ordonnance.date_emission.desc()).all()


@router.post("/ordonnances", response_model=OrdonnanceOut, status_code=status.HTTP_201_CREATED)
def create_ordonnance(ordonnance_data: OrdonnanceCreate, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    consultation = db.query(Consultation).filter(Consultation.id == ordonnance_data.consultation_id, Consultation.is_deleted == False).first()
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation introuvable")
    if not db.query(Patient).filter(Patient.id == consultation.patient_id, Patient.is_deleted == False).first():
        raise HTTPException(status_code=404, detail="Patient introuvable")
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


@router.post("/sync/ordonnances", response_model=OrdonnanceOut)
def sync_ordonnance(ordonnance_data: OrdonnanceSync, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    consultation_id = normalize_uuid(ordonnance_data.consultation_id)
    consultation = db.query(Consultation).filter(Consultation.id == consultation_id, Consultation.is_deleted == False).first()
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation introuvable")
    ordonnance = db.query(Ordonnance).filter(Ordonnance.id == normalize_uuid(ordonnance_data.id)).first()
    if ordonnance is None:
        ordonnance = Ordonnance(id=normalize_uuid(ordonnance_data.id), medecin_id=normalize_uuid(current_user.id))
        db.add(ordonnance)
    elif ordonnance.updated_at and ordonnance_data.updated_at and ordonnance.updated_at > ordonnance_data.updated_at:
        return ordonnance
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


@router.get("/ordonnances/{ordonnance_id}/pdf")
def ordonnance_pdf(ordonnance_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    ordonnance = db.query(Ordonnance).filter(Ordonnance.id == ordonnance_id, Ordonnance.is_deleted == False).first()
    if not ordonnance:
        raise HTTPException(status_code=404, detail="Ordonnance introuvable")
    patient = db.query(Patient).filter(Patient.id == ordonnance.patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient introuvable")
    output_path = os.path.join(tempfile.gettempdir(), f"ordonnance-{ordonnance.id}.pdf")
    document = canvas.Canvas(output_path, pagesize=A4)
    _, height = A4
    document.setTitle("Ordonnance médicale HaD France")
    document.setFont("Helvetica-Bold", 18)
    document.drawString(50, height - 60, "HaD France - Ordonnance médicale")
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
        document.drawString(65, y - 20, ordonnance.instructions_generales[:110])
    document.save()
    return FileResponse(output_path, media_type="application/pdf", filename=f"ordonnance-{ordonnance.id}.pdf")
