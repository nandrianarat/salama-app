# Routeurs backend

Organisation cible de l'API :

- `auth.py` : connexion, inscription et session courante.
- `patients.py` : dossiers patients et synchronisation.
- `consultations.py` : consultations et synchronisation.
- `rendezvous.py` : planning et synchronisation.
- `ordonnances.py` : prescriptions, synchronisation et PDF.

Les schémas communs sont dans `../schemas.py` et les dépendances partagées
dans `../dependencies.py`. Les URLs restent sous `/api/v1` pour conserver
la compatibilité avec `mobile/lib`.
