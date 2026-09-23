import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'local_database.dart';
import 'prescription_pdf.dart';
import 'sync_service.dart';
import 'app_theme.dart';

part 'pages/auth_page.dart';
part 'pages/home_page.dart';
part 'pages/patients_page.dart';
part 'pages/appointments_page.dart';
part 'pages/consultations_page.dart';
part 'pages/prescriptions_page.dart';

const _secureStorage = FlutterSecureStorage();
const _tokenKey = 'salama_access_token';
const _roleKey = 'salama_user_role';
final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

class _AuthSession {
  const _AuthSession({
    required this.token,
    required this.role,
    required this.name,
    this.patientId,
  });

  final String token;
  final String role;
  final String name;
  final String? patientId;
}

void main() => runApp(const SalamaApp());

class SalamaApp extends StatelessWidget {
  const SalamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Rova Santé',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: hadTheme(),
        darkTheme: _darkTheme,
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(0.92),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AuthGate(),
      ),
    );
  }

  static final _darkTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF54C4D8),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF2D2A26),
    useMaterial3: true,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A2730),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<_AuthSession?> _sessionFuture = _restoreSession();

  Future<_AuthSession?> _restoreSession() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final user = jsonDecode(response.body) as Map<String, dynamic>;
        final role =
            user['role'] as String? ??
            await _secureStorage.read(key: _roleKey) ??
            'patient';
        final name = user['nom'] as String? ?? 'Administrateur';
        final patientId = user['patient_id']?.toString();
        await _secureStorage.write(key: _roleKey, value: role);
        return _AuthSession(
          token: token,
          role: role,
          name: name,
          patientId: patientId,
        );
      }
    } catch (_) {
      final role = await _secureStorage.read(key: _roleKey) ?? 'patient';
      return _AuthSession(token: token, role: role, name: 'Administrateur');
    }

    await _secureStorage.delete(key: _tokenKey);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AuthSession?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final session = snapshot.data;
        return session == null || session.token.isEmpty
            ? const WelcomePage()
            : HomePage(
                token: session.token,
                role: session.role,
                displayName: session.name,
                patientId: session.patientId,
              );
      },
    );
  }
}
