import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:service_sante_mobile/main.dart';

void main() {
  testWidgets('affiche la page de connexion actuelle de Rova', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Bienvenue chez Rova'), findsOneWidget);
    expect(find.text('Se connecter'), findsWidgets);
    expect(find.text('Créer un compte'), findsWidgets);
    expect(find.text('Mot de passe oublié ?'), findsWidgets);
    expect(find.text('Rova.'), findsWidgets);
  });

  testWidgets('affiche le message pour un mot de passe trop court', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.enterText(find.byType(TextField).at(0), 'patient');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('Se connecter').last);
    await tester.pump();

    expect(
      find.text(
        'Votre mot de passe doit contenir au moins 6 caractères minimum',
      ),
      findsOneWidget,
    );
  });

  testWidgets('affiche les validations de connexion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.tap(find.text('Se connecter').last);
    await tester.pump();
    expect(
      find.text(
        'Veuillez entrer votre identifiant et votre mot de passe avant de vous connecter',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).at(0), 'patient');
    await tester.tap(find.text('Se connecter').last);
    await tester.pump();
    expect(find.text('Veuillez ajouter votre mot de passe'), findsOneWidget);
  });

  testWidgets('valide les informations du formulaire de compte', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.tap(find.text('Créer un compte').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Aminata Diallo');
    await tester.enterText(find.byType(TextField).at(1), 'aminata');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Veuillez confirmer votre mot de passe'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(3), 'different');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Les mots de passe ne correspondent pas'), findsOneWidget);
  });

  testWidgets('préremplit les champs du formulaire en mode édition patient', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PatientFormPage(
          token: 'demo-token',
          patient: {
            'id': '11111111-1111-4111-8111-111111111111',
            'nom': 'Diallo',
            'prenom': 'Aminata',
            'telephone': '+221771234567',
            'adresse': 'Dakar',
            'date_naissance': '1995-04-12',
            'sexe': 'F',
            'groupe_sanguin': 'O+',
            'allergies': 'Pénicilline',
            'contact_urgence': '+221778765432',
          },
        ),
      ),
    );

    expect(find.text('Modifier le patient'), findsAtLeastNWidgets(1));

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    final values = fields.map((field) => field.controller?.text).toList();
    expect(values, contains('Diallo'));
    expect(values, contains('Aminata'));
    expect(values, contains('Dakar'));
  });
}
