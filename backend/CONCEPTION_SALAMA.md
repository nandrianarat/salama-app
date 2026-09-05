# Salama - Service de Sante

## 1. Objectif

Salama est une application web et mobile de gestion d'un centre de sante. Elle permet aux soignants de gerer les patients, les consultations, les rendez-vous et les ordonnances. Le parcours principal se termine par la generation et la remise d'une ordonnance PDF.

Le projet ne gere pas la pharmacie, le stock, la vente ou la dispensation des medicaments. Les medicaments sont uniquement des lignes d'une ordonnance medicale.

## 2. Architecture cible

- Backend : FastAPI, Python, SQLAlchemy, PostgreSQL
- Application mobile : Flutter, SQLite local
- Application web : React/TypeScript, utilisable avec le backend
- Authentification : JWT avec mots de passe hashes
- Synchronisation : file locale d'operations, puis synchronisation vers PostgreSQL
- Documents : generation d'une ordonnance PDF cote backend et partage cote mobile

## 3. Modules fonctionnels

### Authentification et utilisateurs

- Connexion des soignants avec login et mot de passe
- Token JWT avec expiration
- Roles : administrateur, medecin, infirmier
- Administration des utilisateurs reservee a l'administrateur

### Patients

- Creer, consulter, rechercher, modifier et supprimer logiquement un patient
- Identifiant UUID
- Informations d'identite, contact, antecedents utiles et contact d'urgence

### Consultations

- Creer une consultation pour un patient
- Consulter l'historique des consultations
- Modifier ou supprimer logiquement une consultation
- Associer le soignant authentifie a la consultation

### Rendez-vous

- Creer et consulter les rendez-vous
- Statuts : confirme, annule, termine
- Associer le patient et le soignant

### Ordonnances et PDF

- Creer une ordonnance depuis une consultation
- Ajouter une ou plusieurs lignes de prescription
- Consulter l'ordonnance
- Generer un PDF signe par les informations du centre et du soignant
- Aucun module de pharmacie ou de stock

## 4. Mode offline-first mobile

1. L'utilisateur se connecte lorsqu'une connexion est disponible.
2. Les donnees necessaires sont copiees dans SQLite.
3. Les creations et modifications sont enregistrees localement avec un UUID et un statut `pending`.
4. L'interface reste utilisable sans reseau.
5. Au retour du reseau, les operations sont envoyees au backend.
6. Le serveur confirme chaque operation et l'application passe son statut a `synced`.
7. Les conflits sont signales et ne sont pas ecrases silencieusement.

Les tokens ne seront pas stockes en clair dans SQLite. Ils seront conserves dans le stockage securise du telephone.

## 5. Regles de securite

- Toutes les routes metier necessitent un JWT valide.
- Les permissions sont controlees par role cote backend.
- Les suppressions metier sont logiques avec `is_deleted`.
- Les secrets et identifiants PostgreSQL seront deplaces dans des variables d'environnement.
- Les erreurs API ne doivent pas exposer de mot de passe, token ou requete SQL.

## 6. Ordre de developpement

1. Stabiliser le backend et les migrations PostgreSQL.
2. Finaliser les CRUD patients, consultations, rendez-vous et utilisateurs.
3. Finaliser les ordonnances et la generation PDF.
4. Ajouter les tests API automatises.
5. Creer l'application Flutter et sa base SQLite.
6. Implementer login, stockage securise et synchronisation.
7. Ajouter l'interface web d'administration.
8. Tester le parcours complet hors ligne puis en ligne.

## 7. Parcours principal valide

Connexion -> selection ou creation du patient -> consultation -> ordonnance -> generation PDF -> partage ou impression du PDF.
