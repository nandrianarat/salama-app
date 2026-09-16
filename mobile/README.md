# Service Sante Mobile

Application Flutter de gestion de centre de sante HaD France / Rova.

## Fonctionnalites

- Authentification API avec stockage securise du jeton
- Tableau de bord Rova responsive pour mobile et desktop
- Gestion des patients, rendez-vous, consultations et ordonnances
- Fonctionnement hors-ligne avec file de synchronisation locale
- Generation et partage des prescriptions PDF
- Mode clair et mode sombre

## Demarrage

```bash
flutter pub get
flutter run
```

Pour utiliser une autre adresse de backend :

```bash
flutter run --dart-define=API_BASE_URL=http://adresse-du-backend:8001
```

Le projet est Flutter uniquement. L'ancienne interface Next.js/React a ete retiree.
# service_sante_mobile

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
