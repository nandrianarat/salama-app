import 'dart:convert';
import 'dart:developer' as developer;

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = join(await getDatabasesPath(), 'salama.db');
    _database = await openDatabase(
      path,
      version: 3,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE patients (
            id TEXT PRIMARY KEY,
            nom TEXT NOT NULL,
            prenom TEXT NOT NULL,
            telephone TEXT,
            date_naissance TEXT,
            sexe TEXT,
            adresse TEXT,
            groupe_sanguin TEXT,
            allergies TEXT,
            contact_urgence TEXT,
            sync_status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await database.execute('''
          CREATE TABLE personnel (
            id TEXT PRIMARY KEY, nom TEXT NOT NULL,
            role TEXT NOT NULL, specialite TEXT, numero_ordre TEXT,
            login TEXT NOT NULL UNIQUE, mot_de_passe_hash TEXT,
            sync_status TEXT NOT NULL DEFAULT 'synced',
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await database.execute('''
          CREATE TABLE consultations (
            id TEXT PRIMARY KEY, patient_id TEXT NOT NULL,
            medecin_id TEXT, date TEXT NOT NULL, motif TEXT NOT NULL,
            lieu TEXT NOT NULL DEFAULT 'Cabinet',
            diagnostic TEXT, notes TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (patient_id) REFERENCES patients(id),
            FOREIGN KEY (medecin_id) REFERENCES personnel(id)
          )
        ''');
        await database.execute('''
          CREATE TABLE ordonnances (
            id TEXT PRIMARY KEY, consultation_id TEXT NOT NULL,
            patient_id TEXT NOT NULL, medecin_id TEXT,
            date_emission TEXT NOT NULL, instructions_generales TEXT,
            pdf_local_path TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (consultation_id) REFERENCES consultations(id),
            FOREIGN KEY (patient_id) REFERENCES patients(id),
            FOREIGN KEY (medecin_id) REFERENCES personnel(id)
          )
        ''');
        await database.execute('''
          CREATE TABLE lignes_prescription (
            id TEXT PRIMARY KEY, ordonnance_id TEXT NOT NULL,
            medicament TEXT NOT NULL, dosage TEXT, frequence TEXT, duree TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (ordonnance_id) REFERENCES ordonnances(id)
              ON DELETE CASCADE
          )
        ''');
        await database.execute('''
          CREATE TABLE rendez_vous (
            id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, medecin_id TEXT,
            date_heure TEXT NOT NULL, statut TEXT NOT NULL, motif TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (patient_id) REFERENCES patients(id),
            FOREIGN KEY (medecin_id) REFERENCES personnel(id)
          )
        ''');
        await database.execute('''
          CREATE TABLE pending_operations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_consultations_patient ON consultations(patient_id)',
        );
        await database.execute(
          'CREATE INDEX idx_ordonnances_patient ON ordonnances(patient_id)',
        );
        await database.execute(
          'CREATE INDEX idx_rendez_vous_date ON rendez_vous(date_heure)',
        );
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE patients ADD COLUMN created_at TEXT NOT NULL DEFAULT ''",
          );
          await database.execute('''
            CREATE TABLE personnel (
              id TEXT PRIMARY KEY, nom TEXT NOT NULL, role TEXT NOT NULL,
              specialite TEXT, numero_ordre TEXT, login TEXT NOT NULL UNIQUE,
              mot_de_passe_hash TEXT, sync_status TEXT NOT NULL DEFAULT 'synced',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.execute('''
            CREATE TABLE consultations (
              id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, medecin_id TEXT,
              date TEXT NOT NULL, motif TEXT NOT NULL, diagnostic TEXT,
              notes TEXT, sync_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.execute('''
            CREATE TABLE ordonnances (
              id TEXT PRIMARY KEY, consultation_id TEXT NOT NULL,
              patient_id TEXT NOT NULL, medecin_id TEXT,
              date_emission TEXT NOT NULL, instructions_generales TEXT,
              pdf_local_path TEXT, sync_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.execute('''
            CREATE TABLE lignes_prescription (
              id TEXT PRIMARY KEY, ordonnance_id TEXT NOT NULL,
              medicament TEXT NOT NULL, dosage TEXT, frequence TEXT, duree TEXT,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.execute('''
            CREATE TABLE rendez_vous (
              id TEXT PRIMARY KEY, patient_id TEXT NOT NULL, medecin_id TEXT,
              date_heure TEXT NOT NULL, statut TEXT NOT NULL, motif TEXT,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 3) {
          await database.execute(
            "ALTER TABLE consultations ADD COLUMN lieu TEXT NOT NULL DEFAULT 'Cabinet'",
          );
        }
      },
    );
    return _database!;
  }

  Future<void> savePatient(Map<String, dynamic> patient) async {
    final database = await this.database;
    await database.insert('patients', {
      'id': patient['id'],
      'nom': patient['nom'],
      'prenom': patient['prenom'],
      'telephone': patient['telephone'],
      'date_naissance': patient['date_naissance'],
      'sexe': patient['sexe'],
      'adresse': patient['adresse'],
      'groupe_sanguin': patient['groupe_sanguin'],
      'allergies': patient['allergies'],
      'contact_urgence': patient['contact_urgence'],
      'sync_status': patient['sync_status'] ?? 'synced',
      'created_at':
          patient['created_at'] ??
          patient['updated_at'] ??
          DateTime.now().toIso8601String(),
      'updated_at': patient['updated_at'] ?? DateTime.now().toIso8601String(),
      'is_deleted': patient['is_deleted'] == true ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPatients({String? search}) async {
    final database = await this.database;
    final query = search?.trim();
    final rows = await database.query(
      'patients',
      where: query == null || query.isEmpty
          ? 'is_deleted = 0'
          : 'is_deleted = 0 AND (nom LIKE ? OR prenom LIKE ? OR telephone LIKE ?)',
      whereArgs: query == null || query.isEmpty
          ? null
          : ['%$query%', '%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return rows;
  }

  Future<void> saveConsultation(Map<String, dynamic> consultation) async {
    final database = await this.database;
    await database.insert('consultations', {
      'id': consultation['id'],
      'patient_id': consultation['patient_id'],
      'medecin_id': null,
      'date': consultation['date'] ?? DateTime.now().toIso8601String(),
      'motif': consultation['motif'] ?? '',
      'lieu':
          consultation['lieu'] ??
          _consultationLocationFromNotes(consultation['notes']),
      'diagnostic': consultation['diagnostic'],
      'notes': consultation['notes'],
      'sync_status': consultation['sync_status'] ?? 'synced',
      'created_at':
          consultation['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at':
          consultation['updated_at'] ?? DateTime.now().toIso8601String(),
      'is_deleted': consultation['is_deleted'] == true ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String _consultationLocationFromNotes(Object? notes) =>
      notes?.toString().startsWith('Lieu: Domicile') == true
      ? 'Domicile'
      : 'Cabinet';

  Future<List<Map<String, dynamic>>> getConsultations() async {
    final database = await this.database;
    return database.query(
      'consultations',
      where: 'is_deleted = 0',
      orderBy: 'date DESC',
    );
  }

  Future<void> saveRendezVous(Map<String, dynamic> appointment) async {
    final database = await this.database;
    await database.insert('rendez_vous', {
      'id': appointment['id'],
      'patient_id': appointment['patient_id'],
      'medecin_id': null,
      'date_heure': appointment['date_heure'],
      'statut': appointment['statut'] ?? 'confirme',
      'motif': appointment['motif'],
      'sync_status': appointment['sync_status'] ?? 'synced',
      'created_at':
          appointment['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at':
          appointment['updated_at'] ?? DateTime.now().toIso8601String(),
      'is_deleted': appointment['is_deleted'] == true ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getRendezVous() async {
    final database = await this.database;
    return database.query(
      'rendez_vous',
      where: 'is_deleted = 0',
      orderBy: 'date_heure ASC',
    );
  }

  Future<void> saveOrdonnance(Map<String, dynamic> ordonnance) async {
    final database = await this.database;
    await database.insert('ordonnances', {
      'id': ordonnance['id'],
      'consultation_id': ordonnance['consultation_id'],
      'patient_id': ordonnance['patient_id'],
      'medecin_id': ordonnance['medecin_id'],
      'date_emission':
          ordonnance['date_emission'] ??
          DateTime.now().toIso8601String().substring(0, 10),
      'instructions_generales': ordonnance['instructions_generales'],
      'pdf_local_path': ordonnance['pdf_local_path'],
      'sync_status': ordonnance['sync_status'] ?? 'synced',
      'created_at':
          ordonnance['created_at'] ?? DateTime.now().toIso8601String(),
      'updated_at':
          ordonnance['updated_at'] ?? DateTime.now().toIso8601String(),
      'is_deleted': ordonnance['is_deleted'] == true ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveOrdonnanceWithLines(
    Map<String, dynamic> ordonnance,
    List<Map<String, dynamic>> lines,
  ) async {
    final database = await this.database;
    await database.transaction((transaction) async {
      await transaction.insert('ordonnances', {
        'id': ordonnance['id'],
        'consultation_id': ordonnance['consultation_id'],
        'patient_id': ordonnance['patient_id'],
        'medecin_id': ordonnance['medecin_id'],
        'date_emission': ordonnance['date_emission'],
        'instructions_generales': ordonnance['instructions_generales'],
        'pdf_local_path': ordonnance['pdf_local_path'],
        'sync_status': ordonnance['sync_status'] ?? 'pending',
        'created_at': ordonnance['created_at'],
        'updated_at': ordonnance['updated_at'],
        'is_deleted': ordonnance['is_deleted'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final line in lines) {
        await transaction.insert('lignes_prescription', {
          'id': line['id'],
          'ordonnance_id': ordonnance['id'],
          'medicament': line['medicament'],
          'dosage': line['dosage'],
          'frequence': line['frequence'],
          'duree': line['duree'],
          'sync_status':
              line['sync_status'] ?? ordonnance['sync_status'] ?? 'pending',
          'created_at': line['created_at'] ?? ordonnance['created_at'],
          'updated_at': line['updated_at'] ?? ordonnance['updated_at'],
          'is_deleted': line['is_deleted'] == true ? 1 : 0,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getOrdonnances() async {
    final database = await this.database;
    final ordonnances = await database.query(
      'ordonnances',
      where: 'is_deleted = 0',
      orderBy: 'date_emission DESC',
    );
    final result = <Map<String, dynamic>>[];
    for (final ordonnance in ordonnances) {
      final lines = await database.query(
        'lignes_prescription',
        where: 'ordonnance_id = ? AND is_deleted = 0',
        whereArgs: [ordonnance['id']],
        orderBy: 'created_at ASC',
      );
      result.add({...ordonnance, 'lignes': lines});
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    final database = await this.database;
    return database.query('pending_operations', orderBy: 'id ASC');
  }

  Future<int> getPendingOperationCount() async {
    final database = await this.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS total FROM pending_operations',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<int> addPendingOperation({
    required String entity,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final database = await this.database;
    return database.insert('pending_operations', {
      'entity': entity,
      'entity_id': entityId,
      'operation': operation,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removePendingOperation(int id) async {
    final database = await this.database;
    await database.delete(
      'pending_operations',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> debugDatabase() async {
    final database = await this.database;

    final patients = await database.query('patients');
    final consultations = await database.query('consultations');
    final rendezVous = await database.query('rendez_vous');
    final ordonnances = await database.query('ordonnances');
    final pendingOperations = await database.query(
      'pending_operations',
      orderBy: 'id ASC',
    );

    developer.log('========== BASE LOCALE ==========');

    developer.log('--- PATIENTS (${patients.length}) ---');
    for (final patient in patients) {
      developer.log(patient.toString());
    }

    developer.log('--- CONSULTATIONS (${consultations.length}) ---');
    for (final consultation in consultations) {
      developer.log(consultation.toString());
    }

    developer.log('--- RENDEZ-VOUS (${rendezVous.length}) ---');
    for (final rendezVousItem in rendezVous) {
      developer.log(rendezVousItem.toString());
    }

    developer.log('--- ORDONNANCES (${ordonnances.length}) ---');
    for (final ordonnance in ordonnances) {
      developer.log(ordonnance.toString());
    }

    developer.log('--- PENDING OPERATIONS (${pendingOperations.length}) ---');
    for (final operation in pendingOperations) {
      developer.log(operation.toString());
    }

    developer.log('=================================');
  }
}
