from datetime import date, datetime
import os
import tempfile
from typing import Literal
from uuid import UUID

from fastapi import FastAPI, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from database import engine, get_db, Base, SessionLocal
from models import Consultation, LignePrescription, Ordonnance, Patient, Personnel, RendezVous
from auth import hash_password, verify_password, create_access_token, decode_access_token

# Crée les tables si elles n'existent pas déjà (utile en développement)
Base.metadata.create_all(bind=engine)


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

# Indique à FastAPI où se trouve la route de connexion (pour la doc Swagger)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")


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


@app.post("/api/v1/auth/login")
@app.post("/auth/login")
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(Personnel).filter(Personnel.login == form_data.username).first()

    if not user or not verify_password(form_data.password, user.mot_de_passe_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Identifiant ou mot de passe incorrect",
        )

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {"access_token": token, "token_type": "bearer"}


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    try:
        payload = decode_access_token(token)
        user_id = payload.get("sub")
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalide ou expiré",
        )

    user = db.query(Personnel).filter(Personnel.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Utilisateur introuvable")
    return user


@app.get("/auth/me")
@app.get("/api/v1/auth/me")
def read_current_user(current_user: Personnel = Depends(get_current_user)):
    return {
        "id": str(current_user.id),
        "nom": current_user.nom,
        "role": current_user.role,
    }


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
def get_patient(patient_id: UUID, db: Session = Depends(get_db), current_user: Personnel = Depends(get_current_user)):
    del current_user
    patient = db.query(Patient).filter(Patient.id == patient_id, Patient.is_deleted == False).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient non trouvé")
    return patient


@app.post("/api/v1/patients", response_model=PatientOut, status_code=status.HTTP_201_CREATED)
def create_patient(
    patient_data: PatientCreate,
    db: Session = Depends(get_db),
    current_user: Personnel = Depends(get_current_user),
):
    del current_user
    patient = Patient(**patient_data.model_dump())
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
    patient = db.query(Patient).filter(Patient.id == patient_data.id).first()
    values = patient_data.model_dump(exclude={"id", "updated_at"})
    if patient is None:
        patient = Patient(id=patient_data.id, **values)
        db.add(patient)
    else:
        server_updated = patient.updated_at
        client_updated = patient_data.updated_at
        if server_updated is not None and client_updated is not None and server_updated > client_updated:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Conflit de synchronisation")
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
        patient_id=consultation_data.patient_id,
        medecin_id=current_user.id,
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
    patient = db.query(Patient).filter(
        Patient.id == consultation_data.patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    consultation = db.query(Consultation).filter(Consultation.id == consultation_data.id).first()
    if consultation is None:
        consultation = Consultation(
            id=consultation_data.id,
            patient_id=consultation_data.patient_id,
            medecin_id=current_user.id,
            date=consultation_data.date,
            motif=consultation_data.motif,
            diagnostic=consultation_data.diagnostic,
            notes=consultation_data.notes,
        )
        db.add(consultation)
    else:
        if consultation.updated_at and consultation_data.updated_at and consultation.updated_at > consultation_data.updated_at:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Conflit de synchronisation")
        for field, value in consultation_data.model_dump(exclude={"id", "updated_at", "patient_id"}).items():
            setattr(consultation, field, value)
    consultation.patient_id = consultation_data.patient_id
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
        patient_id=rendezvous_data.patient_id,
        medecin_id=current_user.id,
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
    patient = db.query(Patient).filter(
        Patient.id == rendezvous_data.patient_id,
        Patient.is_deleted == False,
    ).first()
    if not patient:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient introuvable")
    rendezvous = db.query(RendezVous).filter(RendezVous.id == rendezvous_data.id).first()
    if rendezvous is None:
        rendezvous = RendezVous(id=rendezvous_data.id, medecin_id=current_user.id)
        db.add(rendezvous)
    elif rendezvous.updated_at and rendezvous_data.updated_at and rendezvous.updated_at > rendezvous_data.updated_at:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Conflit de synchronisation")
    rendezvous.patient_id = rendezvous_data.patient_id
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
        consultation_id=consultation.id,
        patient_id=consultation.patient_id,
        medecin_id=current_user.id,
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
    consultation = db.query(Consultation).filter(
        Consultation.id == ordonnance_data.consultation_id,
        Consultation.is_deleted == False,
    ).first()
    if not consultation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Consultation introuvable")
    ordonnance = db.query(Ordonnance).filter(Ordonnance.id == ordonnance_data.id).first()
    if ordonnance is None:
        ordonnance = Ordonnance(id=ordonnance_data.id, medecin_id=current_user.id)
        db.add(ordonnance)
    elif ordonnance.updated_at and ordonnance_data.updated_at and ordonnance.updated_at > ordonnance_data.updated_at:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Conflit de synchronisation")
    ordonnance.consultation_id = ordonnance_data.consultation_id
    ordonnance.patient_id = consultation.patient_id
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
