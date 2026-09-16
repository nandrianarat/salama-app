"""Schemas Pydantic partages par les routes FastAPI."""

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class RegisterRequest(BaseModel):
    nom: str = Field(..., min_length=2)
    login: str = Field(..., min_length=3)
    mot_de_passe: str = Field(..., min_length=6)
    role: Literal["medecin", "infirmier", "secretaire", "patient"] = "patient"


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
    lieu: Literal["Cabinet", "Domicile"] | None = None
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


class PersonnelOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    nom: str
    role: str
    specialite: str | None = None
    numero_ordre: str | None = None
    login: str
    created_at: datetime | None = None
    updated_at: datetime | None = None
    sync_status: str
    is_deleted: bool
