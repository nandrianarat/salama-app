import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:service_sante_mobile/main.dart';

void main() {
  testWidgets('Rova affiche la nouvelle interface de connexion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('HaD FRANCE'), findsOneWidget);
    expect(find.text('Être soigné à la maison.'), findsOneWidget);
    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('Mot de passe oublié ?'), findsOneWidget);
    expect(
      find.byTooltip('Afficher ou masquer le mot de passe'),
      findsOneWidget,
    );
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Rova Santé'), findsNothing);
  });

  testWidgets('affiche le message pour un mot de passe trop court', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.enterText(find.byType(TextField).at(0), 'patient');
    await tester.enterText(find.byType(TextField).at(1), '12345');
    await tester.tap(find.text('Se connecter'));
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

    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(
      find.text(
        'Veuillez entrer votre identifiant et votre mot de passe avant de vous connecter',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).at(0), 'patient');
    await tester.tap(find.text('Se connecter'));
    await tester.pump();
    expect(find.text('Veuillez ajouter votre mot de passe'), findsOneWidget);
  });

  testWidgets('valide les informations du formulaire de compte', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.tap(find.text('Créer un compte'));
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
}
