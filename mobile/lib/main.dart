import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'local_database.dart';
import 'prescription_pdf.dart';
import 'sync_service.dart';

const _secureStorage = FlutterSecureStorage();
const _tokenKey = 'salama_access_token';

void main() => runApp(const SalamaApp());

class SalamaApp extends StatelessWidget {
  const SalamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salama - Service de Sante',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF126E69)),
        scaffoldBackgroundColor: const Color(0xFFF4F7F6),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<String?> _tokenFuture = _restoreSession();

  Future<String?> _restoreSession() async {
    final token = await _secureStorage.read(key: _tokenKey);
    if (token == null || token.isEmpty) return null;

    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) return token;
    } catch (_) {
      return token;
    }

    await _secureStorage.delete(key: _tokenKey);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _tokenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final token = snapshot.data;
        return token == null || token.isEmpty
            ? const LoginPage()
            : HomePage(token: token);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  // Android emulator: 10.0.2.2 points to the development computer.
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String get _apiBaseUrl => _configuredApiBaseUrl.isNotEmpty
    ? _configuredApiBaseUrl
    : (kIsWeb ? 'http://localhost:8001' : 'http://192.168.1.65:8001');

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Saisissez votre login et votre mot de passe.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': _usernameController.text.trim(),
          'password': _passwordController.text,
        },
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _secureStorage.write(
          key: _tokenKey,
          value: data['access_token'] as String,
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(token: data['access_token'] as String),
          ),
        );
      } else {
        setState(() => _error = 'Login incorrect. Vérifiez vos identifiants.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Backend inaccessible. Vérifiez le serveur et le réseau.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.health_and_safety_outlined,
                    size: 72,
                    color: Color(0xFF126E69),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Salama',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF126E69),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Service de Sante',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 40),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Connexion soignant',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _usernameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Login',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            onSubmitted: (_) => _login(),
                            decoration: const InputDecoration(
                              labelText: 'Mot de passe',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _loading ? null : _login,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.login),
                            label: Text(
                              _loading ? 'Connexion...' : 'Se connecter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Compte de test : admin / admin123',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Salama',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            onPressed: () async {
              await _secureStorage.delete(key: _tokenKey);
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ListTile(
            leading: Icon(Icons.cloud_done_outlined, color: Color(0xFF126E69)),
            title: Text('Connexion réussie'),
            subtitle: Text('Token JWT reçu avec succès.'),
          ),
          const SizedBox(height: 18),
          Text(
            'Actions rapides',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.person_add_alt_1,
            title: 'Nouveau patient',
            subtitle: 'Enregistrer un patient',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NewPatientPage(token: token)),
            ),
          ),
          _ActionTile(
            icon: Icons.medical_information_outlined,
            title: 'Consultation',
            subtitle: 'Ouvrir une consultation',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConsultationsPage(token: token),
              ),
            ),
          ),
          _ActionTile(
            icon: Icons.calendar_month_outlined,
            title: 'Rendez-vous',
            subtitle: 'Voir le planning',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RendezVousPage(token: token)),
            ),
          ),
          _ActionTile(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Ordonnance PDF',
            subtitle: 'Créer le document final',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OrdonnancesPage(token: token)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Patients',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            label: 'Planning',
          ),
        ],
        onDestinationSelected: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PatientsPage(token: token)),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RendezVousPage(token: token)),
            );
          }
        },
      ),
    );
  }
}

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key, required this.token});

  final String token;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late Future<List<Map<String, dynamic>>> _patientsFuture;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _patientsFuture = _loadPatients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadPatients([String? search]) async {
    final query = search?.trim();
    final uri = Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients')
        .replace(
          queryParameters: query == null || query.isEmpty ? null : {'q': query},
        );
    try {
      await SyncService(
        baseUrl: _LoginPageState._apiBaseUrl,
        token: widget.token,
      ).syncPendingPatients();
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Erreur de chargement (${response.statusCode})');
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      final patients = data.cast<Map<String, dynamic>>();
      for (final patient in patients) {
        await LocalDatabase.instance.savePatient(patient);
      }
      return patients;
    } catch (_) {
      final localPatients = await LocalDatabase.instance.getPatients(
        search: query,
      );
      if (localPatients.isNotEmpty) return localPatients;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Patients',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => NewPatientPage(token: widget.token),
            ),
          );
          if (created == true && mounted) {
            setState(() => _patientsFuture = _loadPatients());
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nouveau'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) =>
                  setState(() => _patientsFuture = _loadPatients(value)),
              decoration: InputDecoration(
                labelText: 'Rechercher un patient',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Effacer la recherche',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _patientsFuture = _loadPatients());
                  },
                  icon: const Icon(Icons.clear),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _patientsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Impossible de charger les patients.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final patients = snapshot.data ?? [];
                if (patients.isEmpty) {
                  return const Center(child: Text('Aucun patient enregistré.'));
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      setState(() => _patientsFuture = _loadPatients()),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: patients.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return Card(
                        elevation: 0,
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(
                            '${patient['prenom']} ${patient['nom']}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            patient['telephone']?.toString() ??
                                'Téléphone non renseigné',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class OrdonnancesPage extends StatefulWidget {
  const OrdonnancesPage({super.key, required this.token});

  final String token;

  @override
  State<OrdonnancesPage> createState() => _OrdonnancesPageState();
}

class _OrdonnancesPageState extends State<OrdonnancesPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.token}',
    'Content-Type': 'application/json',
  };

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/ordonnances'),
        headers: _headers,
      );
      if (response.statusCode != 200) throw Exception('Erreur de chargement');
      final ordonnances = (jsonDecode(response.body) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final ordonnance in ordonnances) {
        final lines = (ordonnance['lignes'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        await LocalDatabase.instance.saveOrdonnanceWithLines(ordonnance, lines);
      }
      return ordonnances;
    } catch (_) {
      final local = await LocalDatabase.instance.getOrdonnances();
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadConsultations() async {
    return LocalDatabase.instance.getConsultations();
  }

  Future<void> _create() async {
    final consultations = await _loadConsultations();
    if (!mounted) return;
    if (consultations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d’abord une consultation.')),
      );
      return;
    }
    String consultationId = consultations.first['id'] as String;
    String patientId = consultations.first['patient_id'] as String;
    final medicineController = TextEditingController();
    final dosageController = TextEditingController();
    final frequencyController = TextEditingController();
    final durationController = TextEditingController();
    final instructionsController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nouvelle ordonnance'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: consultationId,
                decoration: const InputDecoration(labelText: 'Consultation'),
                items: consultations.map((consultation) {
                  return DropdownMenuItem(
                    value: consultation['id'] as String,
                    child: Text(
                      consultation['motif']?.toString() ?? 'Consultation',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    consultationId = value;
                    final selected = consultations.firstWhere(
                      (consultation) => consultation['id'] == value,
                    );
                    patientId = selected['patient_id'] as String;
                  }
                },
              ),
              TextField(
                controller: medicineController,
                decoration: const InputDecoration(labelText: 'Médicament *'),
              ),
              TextField(
                controller: dosageController,
                decoration: const InputDecoration(labelText: 'Dosage'),
              ),
              TextField(
                controller: frequencyController,
                decoration: const InputDecoration(labelText: 'Fréquence'),
              ),
              TextField(
                controller: durationController,
                decoration: const InputDecoration(labelText: 'Durée'),
              ),
              TextField(
                controller: instructionsController,
                decoration: const InputDecoration(
                  labelText: 'Instructions générales',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (medicineController.text.trim().length < 2) return;
              final now = DateTime.now().toUtc().toIso8601String();
              final ordonnanceId = const Uuid().v4();
              final line = <String, dynamic>{
                'id': const Uuid().v4(),
                'medicament': medicineController.text.trim(),
                'dosage': dosageController.text.trim().isEmpty
                    ? null
                    : dosageController.text.trim(),
                'frequence': frequencyController.text.trim().isEmpty
                    ? null
                    : frequencyController.text.trim(),
                'duree': durationController.text.trim().isEmpty
                    ? null
                    : durationController.text.trim(),
                'sync_status': 'pending',
                'created_at': now,
                'updated_at': now,
                'is_deleted': false,
              };
              final payload = <String, dynamic>{
                'id': ordonnanceId,
                'consultation_id': consultationId,
                'patient_id': patientId,
                'date_emission': now.substring(0, 10),
                'instructions_generales':
                    instructionsController.text.trim().isEmpty
                    ? null
                    : instructionsController.text.trim(),
                'lignes': [line],
                'sync_status': 'pending',
                'created_at': now,
                'updated_at': now,
                'is_deleted': false,
              };
              final operationId = await LocalDatabase.instance
                  .addPendingOperation(
                    entity: 'ordonnance',
                    entityId: ordonnanceId,
                    operation: 'upsert',
                    payload: payload,
                  );
              try {
                await LocalDatabase.instance.saveOrdonnanceWithLines(payload, [
                  line,
                ]);
              } catch (_) {
                await LocalDatabase.instance.removePendingOperation(
                  operationId,
                );
                rethrow;
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    medicineController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    durationController.dispose();
    instructionsController.dispose();
    if (created == true && mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ordonnances')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final prescriptions = snapshot.data ?? [];
          if (prescriptions.isEmpty) {
            return const Center(child: Text('Aucune ordonnance enregistrée.'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: prescriptions.length,
              itemBuilder: (context, index) {
                final prescription = prescriptions[index];
                final lines = (prescription['lignes'] as List<dynamic>? ?? []);
                final medicine = lines.isEmpty
                    ? 'Aucun médicament'
                    : (lines.first as Map<String, dynamic>)['medicament']
                          .toString();
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(medicine),
                    subtitle: Text('Émise le ${prescription['date_emission']}'),
                    trailing: IconButton(
                      tooltip: 'Exporter et partager le PDF',
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      onPressed: () async {
                        try {
                          final patient =
                              (prescription['patient']
                                  as Map<String, dynamic>?) ??
                              <String, dynamic>{
                                'nom': prescription['patient_nom'] ?? '',
                                'prenom': prescription['patient_prenom'] ?? '',
                              };
                          final doctor =
                              (prescription['medecin']
                                  as Map<String, dynamic>?) ??
                              <String, dynamic>{
                                'nom': prescription['medecin_nom'] ?? '',
                                'specialite': prescription['specialite'],
                                'numero_ordre': prescription['numero_ordre'],
                              };
                          final path = await exportPrescriptionPdf(
                            prescription: prescription,
                            patient: patient,
                            doctor: doctor,
                          );
                          await sharePrescriptionPdf(path);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Export impossible : $error'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class RendezVousPage extends StatefulWidget {
  const RendezVousPage({super.key, required this.token});

  final String token;

  @override
  State<RendezVousPage> createState() => _RendezVousPageState();
}

class _RendezVousPageState extends State<RendezVousPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/rendezvous'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Erreur de chargement');
      }
      final appointments = (jsonDecode(response.body) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final appointment in appointments) {
        await LocalDatabase.instance.saveRendezVous(appointment);
      }
      return appointments;
    } catch (_) {
      final local = await LocalDatabase.instance.getRendezVous();
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadPatients() async {
    final response = await http.get(
      Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    if (response.statusCode != 200) throw Exception('Patients indisponibles');
    return (jsonDecode(response.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<void> _create() async {
    final patients = await _loadPatients();
    if (!mounted) return;
    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d’abord un patient.')),
      );
      return;
    }
    String patientId = patients.first['id'] as String;
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));
    final motifController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouveau rendez-vous'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: patientId,
                decoration: const InputDecoration(labelText: 'Patient'),
                items: patients
                    .map(
                      (patient) => DropdownMenuItem(
                        value: patient['id'] as String,
                        child: Text('${patient['prenom']} ${patient['nom']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => patientId = value);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  MaterialLocalizations.of(
                    context,
                  ).formatFullDate(selectedDate),
                ),
                subtitle: Text(
                  TimeOfDay.fromDateTime(selectedDate).format(context),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    initialDate: selectedDate,
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                  );
                  if (time != null) {
                    setDialogState(
                      () => selectedDate = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ),
                    );
                  }
                },
              ),
              TextField(
                controller: motifController,
                decoration: const InputDecoration(labelText: 'Motif'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final now = DateTime.now().toUtc().toIso8601String();
                final rendezVousId = const Uuid().v4();

                final payload = <String, dynamic>{
                  'id': rendezVousId,
                  'patient_id': patientId,
                  'date_heure': selectedDate.toUtc().toIso8601String(),
                  'statut': 'confirme',
                  'motif': motifController.text.trim().isEmpty
                      ? null
                      : motifController.text.trim(),
                  'sync_status': 'pending',
                  'created_at': now,
                  'updated_at': now,
                  'is_deleted': false,
                };

                try {
                  // 1. Enregistrer dans SQLite
                  await LocalDatabase.instance.saveRendezVous(payload);

                  // 2. Ajouter dans pending_operations
                  await LocalDatabase.instance.addPendingOperation(
                    entity: 'rendez_vous',
                    entityId: rendezVousId,
                    operation: 'upsert',
                    payload: payload,
                  );

                  // 3. Essayer de synchroniser avec le serveur
                  try {
                    await SyncService(
                      baseUrl: _LoginPageState._apiBaseUrl,
                      token: widget.token,
                    ).syncPendingRendezVous();
                  } catch (_) {
                    // Pas de connexion :
                    // le rendez-vous reste dans SQLite.
                  }

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Enregistrement impossible : $error'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    motifController.dispose();
    if (created == true && mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Planning')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final appointments = snapshot.data ?? [];
          if (appointments.isEmpty) {
            return const Center(child: Text('Aucun rendez-vous enregistré.'));
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: appointments.length,
              itemBuilder: (context, index) {
                final appointment = appointments[index];
                final date = DateTime.tryParse(
                  appointment['date_heure'].toString(),
                );
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.event_available),
                    title: Text(
                      appointment['motif']?.toString() ?? 'Rendez-vous',
                    ),
                    subtitle: Text(
                      date == null
                          ? 'Date indisponible'
                          : '${MaterialLocalizations.of(context).formatFullDate(date)} à ${TimeOfDay.fromDateTime(date).format(context)}',
                    ),
                    trailing: Text(appointment['statut'].toString()),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class NewPatientPage extends StatefulWidget {
  const NewPatientPage({super.key, required this.token});

  final String token;

  @override
  State<NewPatientPage> createState() => _NewPatientPageState();
}

class _NewPatientPageState extends State<NewPatientPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _telephoneController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _telephoneController.dispose();
    super.dispose();
  }

  String? _requiredName(String? value) {
    return value == null || value.trim().length < 2
        ? 'Minimum 2 caractères'
        : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final patientId = const Uuid().v4();
    final payload = {
      'id': patientId,
      'nom': _nomController.text.trim(),
      'prenom': _prenomController.text.trim(),
      'telephone': _telephoneController.text.trim().isEmpty
          ? null
          : _telephoneController.text.trim(),
      'sync_status': 'pending',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'is_deleted': false,
    };
    final operationId = await LocalDatabase.instance.addPendingOperation(
      entity: 'patient',
      entityId: patientId,
      operation: 'upsert',
      payload: payload,
    );
    await LocalDatabase.instance.savePatient(payload);
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/sync/patients'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (!mounted) return;
      if (response.statusCode == 201) {
        await LocalDatabase.instance.removePendingOperation(operationId);
        await LocalDatabase.instance.savePatient(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } else if (response.statusCode == 200) {
        await LocalDatabase.instance.removePendingOperation(operationId);
        await LocalDatabase.instance.savePatient(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau patient')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _nomController,
              validator: _requiredName,
              decoration: const InputDecoration(
                labelText: 'Nom *',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _prenomController,
              validator: _requiredName,
              decoration: const InputDecoration(
                labelText: 'Prénom *',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _telephoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_loading ? 'Enregistrement...' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

class ConsultationsPage extends StatefulWidget {
  const ConsultationsPage({super.key, required this.token});

  final String token;

  @override
  State<ConsultationsPage> createState() => _ConsultationsPageState();
}

class _ConsultationsPageState extends State<ConsultationsPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/consultations'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Erreur de chargement (${response.statusCode})');
      }
      final consultations = (jsonDecode(response.body) as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final consultation in consultations) {
        await LocalDatabase.instance.saveConsultation(consultation);
      }
      return consultations;
    } catch (_) {
      final local = await LocalDatabase.instance.getConsultations();
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consultations')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => NewConsultationPage(token: widget.token,)),
          );
          if (created == true && mounted) {
            setState(() => _future = LocalDatabase.instance.getConsultations());
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final consultations = snapshot.data ?? [];
          if (consultations.isEmpty) {
            return const Center(
              child: Text('Aucune consultation enregistrée.'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: consultations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final consultation = consultations[index];
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.medical_information_outlined),
                    title: Text(
                      consultation['motif']?.toString() ?? 'Consultation',
                    ),
                    subtitle: Text(
                      consultation['diagnostic']?.toString() ??
                          'Aucun diagnostic renseigné',
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class NewConsultationPage extends StatefulWidget {
  const NewConsultationPage({
    super.key,
    required this.token,
  });

  final String token;

  @override
  State<NewConsultationPage> createState() => _NewConsultationPageState();
}

class _NewConsultationPageState extends State<NewConsultationPage> {
  final _formKey = GlobalKey<FormState>();
  final _motifController = TextEditingController();
  final _diagnosticController = TextEditingController();
  final _notesController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _patientsFuture;
  String? _patientId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _patientsFuture = LocalDatabase.instance.getPatients();
  }

  @override
  void dispose() {
    _motifController.dispose();
    _diagnosticController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _patientId == null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final consultationId = const Uuid().v4();
    final payload = <String, dynamic>{
      'id': consultationId,
      'patient_id': _patientId,
      'date': now,
      'motif': _motifController.text.trim(),
      'diagnostic': _diagnosticController.text.trim().isEmpty
          ? null
          : _diagnosticController.text.trim(),
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
      'is_deleted': false,
    };

    setState(() => _saving = true);
    try {
      final operationId = await LocalDatabase.instance.addPendingOperation(
        entity: 'consultation',
        entityId: consultationId,
        operation: 'upsert',
        payload: payload,
      );
      try {
        await LocalDatabase.instance.saveConsultation(payload);
        try {
              await SyncService(
                baseUrl: _LoginPageState._apiBaseUrl,
                token: widget.token,
              ).syncPendingConsultations();
            } catch (_) {
              // Pas de connexion :
              // la consultation reste dans SQLite.
            }
      } catch (_) {
        await LocalDatabase.instance.removePendingOperation(operationId);
        rethrow;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle consultation')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _patientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur SQLite : ${snapshot.error}'));
          }
          final patients = snapshot.data ?? [];
          if (patients.isEmpty) {
            return const Center(
              child: Text('Enregistrez d’abord un patient localement.'),
            );
          }
          _patientId ??= patients.first['id'] as String;
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _patientId,
                  decoration: const InputDecoration(
                    labelText: 'Patient *',
                    border: OutlineInputBorder(),
                  ),
                  items: patients
                      .map(
                        (patient) => DropdownMenuItem<String>(
                          value: patient['id'] as String,
                          child: Text('${patient['prenom']} ${patient['nom']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _patientId = value),
                  validator: (value) =>
                      value == null ? 'Sélectionnez un patient' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _motifController,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Le motif est obligatoire'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Motif *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _diagnosticController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Diagnostic',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'Enregistrement...' : 'Enregistrer localement',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE2F2EE),
          foregroundColor: const Color(0xFF126E69),
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
