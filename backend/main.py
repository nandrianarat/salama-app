from datetime import date, datetime
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
from models import Consultation, LignePrescription, Ordonnance, Patient, Personnel, RendezVous
from auth import hash_password, verify_password, create_access_token, decode_access_token
from dependencies import get_current_user, normalize_uuid
from routers.auth import router as auth_router
from schemas import PersonnelOut

# Crée les tables si elles n'existent pas déjà (utile en développement)
Base.metadata.create_all(bind=engine)


def ensure_schema_updates():
    inspector = inspect(engine)
    if "consultation" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("consultation")}
    if "lieu" in columns:
        return
    with engine.begin() as connection:
        connection.execute(
            text(
                "ALTER TABLE consultation ADD COLUMN lieu VARCHAR(20) "
                "NOT NULL DEFAULT 'Cabinet'"
            )
        )


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


@app.get("/api/v1/personnel", response_model=list[PersonnelOut])
@app.get("/api/v1/users", response_model=list[PersonnelOut])
def list_personnel(
    role: str | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    query = db.query(Personnel).filter(Personnel.is_deleted == False)
    if role:
        query = query.filter(Personnel.role == role)
    return query.order_by(Personnel.created_at.asc()).all()


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
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool


class ConsultationCreate(BaseModel):
    patient_id: UUID
    lieu: Literal["Cabinet", "Domicile"] = "Cabinet"
    motif: str | None = None
    diagnostic: str | None = None
    notes: str | None = None


class ConsultationUpdate(BaseModel):
    motif: str | None = None
    diagnostic: str | None = None
    notes: str | None = None


class ConsultationSync(BaseModel):
    id: UUID
    patient_id: UUID
    lieu: Literal["Cabinet", "Domicile"] = "Cabinet"
    motif: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    date: datetime | None = None
    updated_at: datetime | None = None
    is_deleted: bool = False


class ConsultationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    patient_id: UUID
    medecin_id: UUID
    lieu: str = "Cabinet"
    date: datetime | None = None
    motif: str | None = None
    diagnostic: str | None = None
    notes: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool


class RendezVousCreate(BaseModel):
    patient_id: UUID
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

@app.get("/api/v1/patients", response_model=list[PatientOut])
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
            (Patient.nom.ilike(search)) |
            (Patient.prenom.ilike(search)) |
            (Patient.telephone.ilike(search))
        )
    return query.order_by(Patient.created_at.desc()).all()


@app.get("/api/v1/patients/{patient_id}", response_model=PatientOut)
def ensure_schema_updates():
    """Apply the small additive migrations used by the mobile client."""
    if engine.url.get_backend_name() != "sqlite":
        return
    with engine.begin() as connection:
        columns = connection.exec_driver_sql("PRAGMA table_info(consultation)").fetchall()
        if columns and not any(column[1] == "lieu" for column in columns):
            connection.exec_driver_sql(
                "ALTER TABLE consultation ADD COLUMN lieu VARCHAR(20) NOT NULL DEFAULT 'Cabinet'"
            )

ensure_schema_updates()
def get_patient(patient_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    return patient
    lieu: Literal["Cabinet", "Domicile"] = "Cabinet"


@app.post("/api/v1/patients", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
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


@app.post("/api/v1/sync/patients", response_model=PatientOut)
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
        server_updated = patient.updated_at
        client_updated = patient_data.updated_at
        if server_updated is not None and client_updated is not None and server_updated > client_updated:
            return patient
        for field, value in values.items():
            setattr(patient, field, value)
    patient.sync_status = "synced"
    patient.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(patient)
    return patient


@app.put("/api/v1/patients/{patient_id}", response_model=PatientOut)
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


@app.delete("/api/v1/patients/{patient_id}")
def delete_patient(patient_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
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
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    query = db.query(Consultation).filter(Consultation.is_deleted == False)
    if patient_id:
        query = query.filter(Consultation.patient_id == patient_id)
    return query.order_by(Consultation.created_at.desc()).all()


@app.post("/api/v1/consultations", response_model=ConsultationOut, status_code=status.HTTP_201_CREATED)
def create_consultation(
    consultation_data: ConsultationCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    patient = db.query(Patient).filter(Patient.id == consultation_data.patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")

    consultation = Consultation(
        patient_id=normalize_uuid(consultation_data.patient_id),
        medecin_id=normalize_uuid(current_user.id),
        lieu=consultation_data.lieu,
        motif=consultation_data.motif,
        diagnostic=consultation_data.diagnostic,
        notes=consultation_data.notes,
    )
    db.add(consultation)
    db.commit()
    db.refresh(consultation)
    return consultation


@app.post("/api/v1/sync/consultations", response_model=ConsultationOut)
def sync_consultation(
    consultation_data: ConsultationSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    patient_id = normalize_uuid(consultation_data.patient_id)
    patient = db.query(Patient).filter(
        Patient.id == patient_id,
        Patient.is_deleted == False,
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
            diagnostic=consultation_data.diagnostic,
            notes=consultation_data.notes,
        )
        db.add(consultation)
    else:
        if consultation.updated_at and consultation_data.updated_at and consultation.updated_at > consultation_data.updated_at:
            return consultation
        for field, value in consultation_data.model_dump(exclude={"id", "updated_at", "patient_id"}).items():
            setattr(consultation, field, value)
    consultation.patient_id = patient_id
    consultation.lieu = consultation_data.lieu
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
    current_user: Personnel = Depends(get_current_user),
):
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")

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
    current_user: Personnel = Depends(get_current_user),
):
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")

    consultation.is_deleted = True
    consultation.sync_status = "deleted"
    consultation.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Consultation supprimée avec succès"}


@app.get("/api/v1/rendezvous", response_model=list[RendezVousOut])
def list_rendezvous(
    patient_id: UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    query = db.query(RendezVous).filter(RendezVous.is_deleted == False)
    if patient_id:
        query = query.filter(RendezVous.patient_id == patient_id)
    return query.order_by(RendezVous.date_heure.asc()).all()


@app.post("/api/v1/rendezvous", response_model=RendezVousOut, status_code=status.HTTP_201_CREATED)
def create_rendezvous(
    rendezvous_data: RendezVousCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    patient = db.query(Patient).filter(
        Patient.id == rendezvous_data.patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")

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


@app.post("/api/v1/sync/rendezvous", response_model=RendezVousOut)
def sync_rendezvous(
    rendezvous_data: RendezVousSync,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
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
    current_user: Personnel = Depends(get_current_user),
):
    rendezvous = db.query(RendezVous).filter(
        RendezVous.id == rendezvous_id,
        RendezVous.is_deleted == False,
    ).first()
    if not rendezvous:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rendez-vous introuvable")

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
    current_user: Personnel = Depends(get_current_user),
):
    rendezvous = db.query(RendezVous).filter(
        RendezVous.id == rendezvous_id,
        RendezVous.is_deleted == False,
    ).first()
    if not rendezvous:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Rendez-vous introuvable")

    rendezvous.is_deleted = True
    rendezvous.sync_status = "deleted"
    rendezvous.updated_at = datetime.utcnow()
    db.commit()
    return {"detail": "Rendez-vous supprimé avec succès"}


@app.get("/api/v1/ordonnances", response_model=list[OrdonnanceOut])
def list_ordonnances(
    patient_id: UUID | None = Query(default=None),
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    query = db.query(Ordonnance).filter(Ordonnance.is_deleted == False)
    if patient_id:
        query = query.filter(Ordonnance.patient_id == patient_id)
    return query.order_by(Ordonnance.date_emission.desc()).all()


@app.post("/api/v1/ordonnances", response_model=OrdonnanceOut, status_code=status.HTTP_201_CREATED)
def create_ordonnance(
    ordonnance_data: OrdonnanceCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
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
    current_user: Personnel = Depends(get_current_user),
):
    consultation_id = normalize_uuid(ordonnance_data.consultation_id)
    consultation = db.query(Consultation).filter(
        Consultation.id == consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
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


@app.get("/api/v1/ordonnances/{ordonnance_id}/pdf")
def ordonnance_pdf(
    ordonnance_id: UUID,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    ordonnance = db.query(Ordonnance).filter(
        Ordonnance.id == ordonnance_id,
        Ordonnance.is_deleted == False,
    ).first()
    if not ordonnance:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Ordonnance introuvable")

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
