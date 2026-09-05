import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_database.dart';

class SyncService {
  SyncService({
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Synchronisation générale.
  ///
  /// L'ordre est important :
  /// 1. Patients
  /// 2. Consultations
  /// 3. Rendez-vous
  /// 4. Ordonnances
  Future<void> syncAll() async {
    await syncPendingPatients();
    await syncPendingConsultations();
    await syncPendingRendezVous();
    await syncPendingOrdonnances();
  }

  Future<void> syncPendingPatients() async {
    final pending = await LocalDatabase.instance.getPendingOperations();

    for (final operation in pending) {
      if (operation['entity'] != 'patient') continue;

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/sync/patients'),
        headers: _headers,
        body: operation['payload'] as String,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final patient =
            jsonDecode(response.body) as Map<String, dynamic>;

        await LocalDatabase.instance.savePatient(patient);

        await LocalDatabase.instance.removePendingOperation(
          operation['id'] as int,
        );
      } else if (response.statusCode == 409) {
        throw Exception('Conflit de synchronisation du patient');
      } else {
        throw Exception(
          'Synchronisation du patient impossible '
          '(HTTP ${response.statusCode})',
        );
      }
    }
  }

  Future<void> syncPendingConsultations() async {
    final pending =
        await LocalDatabase.instance.getPendingOperations();

    for (final operation in pending) {
      if (operation['entity'] != 'consultation') continue;

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/sync/consultations'),
        headers: _headers,
        body: operation['payload'] as String,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final consultation =
            jsonDecode(response.body) as Map<String, dynamic>;

        await LocalDatabase.instance.saveConsultation(
          consultation,
        );

        await LocalDatabase.instance.removePendingOperation(
          operation['id'] as int,
        );
      } else if (response.statusCode == 409) {
        throw Exception(
          'Conflit de synchronisation de la consultation',
        );
      } else {
        throw Exception(
          'Synchronisation de la consultation impossible '
          '(HTTP ${response.statusCode})',
        );
      }
    }
  }

  Future<void> syncPendingRendezVous() async {
    final pending =
        await LocalDatabase.instance.getPendingOperations();

    for (final operation in pending) {
      if (operation['entity'] != 'rendez_vous') continue;

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/sync/rendezvous'),
        headers: _headers,
        body: operation['payload'] as String,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final appointment =
            jsonDecode(response.body) as Map<String, dynamic>;

        await LocalDatabase.instance.saveRendezVous(
          appointment,
        );

        await LocalDatabase.instance.removePendingOperation(
          operation['id'] as int,
        );
      } else if (response.statusCode == 409) {
        throw Exception(
          'Conflit de synchronisation du rendez-vous',
        );
      } else {
        throw Exception(
          'Synchronisation du rendez-vous impossible '
          '(HTTP ${response.statusCode})',
        );
      }
    }
  }

  Future<void> syncPendingOrdonnances() async {
    final pending =
        await LocalDatabase.instance.getPendingOperations();

    final pendingConsultationIds = pending
        .where(
          (operation) => operation['entity'] == 'consultation',
        )
        .map(
          (operation) => operation['entity_id'] as String,
        )
        .toSet();

    for (final operation in pending) {
      if (operation['entity'] != 'ordonnance') continue;

      final payload = jsonDecode(
        operation['payload'] as String,
      ) as Map<String, dynamic>;

      final consultationId =
          payload['consultation_id'] as String;

      // On attend que la consultation soit synchronisée.
      if (pendingConsultationIds.contains(consultationId)) {
        continue;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/sync/ordonnances'),
        headers: _headers,
        body: operation['payload'] as String,
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        final ordonnance =
            jsonDecode(response.body) as Map<String, dynamic>;

        final lines =
            (ordonnance['lignes'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();

        await LocalDatabase.instance.saveOrdonnanceWithLines(
          ordonnance,
          lines,
        );

        await LocalDatabase.instance.removePendingOperation(
          operation['id'] as int,
        );
      } else if (response.statusCode == 404) {
        throw Exception(
          'Consultation introuvable côté serveur',
        );
      } else if (response.statusCode == 409) {
        throw Exception(
          'Conflit de synchronisation de l’ordonnance',
        );
      } else {
        throw Exception(
          'Synchronisation de l’ordonnance impossible '
          '(HTTP ${response.statusCode})',
        );
      }
    }
  }
}