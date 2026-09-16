import uuid
from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, String, Text
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base


class Personnel(Base):
    __tablename__ = "personnel"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    nom = Column(String(150), nullable=False)
    role = Column(String(20), nullable=False)
    specialite = Column(String(150))
    numero_ordre = Column(String(50))
    login = Column(String(100), unique=True, nullable=False)
    mot_de_passe_hash = Column(String(255), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    consultations = relationship("Consultation", back_populates="personnel")


class Patient(Base):
    __tablename__ = "patient"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    nom = Column(String(150), nullable=False)
    prenom = Column(String(150), nullable=False)
    date_naissance = Column(Date, nullable=True)
    sexe = Column(String(20), nullable=True)
    telephone = Column(String(30), nullable=True)
    adresse = Column(String(255), nullable=True)
    groupe_sanguin = Column(String(20), nullable=True)
    allergies = Column(Text, nullable=True)
    contact_urgence = Column(String(30), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    consultations = relationship("Consultation", back_populates="patient")


class Consultation(Base):
    __tablename__ = "consultation"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    patient_id = Column(String(36), ForeignKey("patient.id"), nullable=False)
    medecin_id = Column(String(36), ForeignKey("personnel.id"), nullable=False)
    date = Column(DateTime(timezone=True), server_default=func.now())
    lieu = Column(String(20), nullable=False, default="Cabinet")
    motif = Column(String(255), nullable=True)
    diagnostic = Column(Text, nullable=True)
    notes = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    patient = relationship("Patient", back_populates="consultations")
    personnel = relationship("Personnel", back_populates="consultations")
    ordonnances = relationship("Ordonnance", back_populates="consultation")


class RendezVous(Base):
    __tablename__ = "rendezvous"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    patient_id = Column(String(36), ForeignKey("patient.id"), nullable=False)
    medecin_id = Column(String(36), ForeignKey("personnel.id"), nullable=False)
    date_heure = Column(DateTime, nullable=False)
    statut = Column(String(30), nullable=False, default="confirme")
    motif = Column(String(255), nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    patient = relationship("Patient")
    personnel = relationship("Personnel")


class Ordonnance(Base):
    __tablename__ = "ordonnance"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    consultation_id = Column(String(36), ForeignKey("consultation.id"), nullable=False)
    patient_id = Column(String(36), ForeignKey("patient.id"), nullable=False)
    medecin_id = Column(String(36), ForeignKey("personnel.id"), nullable=False)
    date_emission = Column(Date, nullable=False, server_default=func.current_date())
    instructions_generales = Column(Text, nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    consultation = relationship("Consultation", back_populates="ordonnances")
    lignes = relationship("LignePrescription", back_populates="ordonnance")


class LignePrescription(Base):
    __tablename__ = "ligneprescription"

    id = Column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    ordonnance_id = Column(String(36), ForeignKey("ordonnance.id"), nullable=False)
    medicament = Column(String(150), nullable=False)
    dosage = Column(String(100), nullable=True)
    frequence = Column(String(100), nullable=True)
    duree = Column(String(100), nullable=True)

    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    sync_status = Column(String(20), default="synced")
    is_deleted = Column(Boolean, default=False)

    ordonnance = relationship("Ordonnance", back_populates="lignes")
