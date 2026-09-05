import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:service_sante_mobile/main.dart';

void main() {
  testWidgets('Salama affiche la connexion', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Salama'), findsOneWidget);
    expect(find.text('Connexion soignant'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
