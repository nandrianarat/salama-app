# Pages Flutter

Chaque ecran possede un point d'entree dedie :

- `dashboard_page.dart` : tableau de bord apres connexion.
- `patients_page.dart` : liste patients et formulaire patient.
- `appointments_page.dart` : rendez-vous et planning.
- `consultations_page.dart` : consultations et formulaire consultation.
- `prescriptions_page.dart` : ordonnances et telechargement PDF.

Ces fichiers sont des `part` de `main.dart` afin de partager les services,
le theme et les modeles internes sans changer les contrats existants.
Les routes de `HomePage` utilisent ces points d'entree et les implementations
de pages sont maintenues dans leurs fichiers dedies.
