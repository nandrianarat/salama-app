part of '../main.dart';

/// Prescriptions feature entry point.
class PrescriptionsPage extends StatelessWidget {
  const PrescriptionsPage({
    super.key,
    required this.token,
    this.patientId,
    this.canCreate = true,
  });

  final String token;
  final String? patientId;
  final bool canCreate;

  @override
  Widget build(BuildContext context) =>
      OrdonnancesPage(token: token, patientId: patientId, canCreate: canCreate);
}

class OrdonnancesPage extends StatefulWidget {
  const OrdonnancesPage({
    super.key,
    required this.token,
    this.patientId,
    this.canCreate = true,
  });

  final String token;
  final String? patientId;
  final bool canCreate;

  @override
  State<OrdonnancesPage> createState() => _OrdonnancesPageState();
}

class _OrdonnancesPageState extends State<OrdonnancesPage> {
  late Future<List<Map<String, dynamic>>> _future;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${widget.token}',
    'Content-Type': 'application/json',
  };

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final uri = Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/ordonnances')
          .replace(
            queryParameters: widget.patientId == null
                ? null
                : {'patient_id': widget.patientId!},
          );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        throw Exception('Erreur de chargement (${response.statusCode})');
      }
      final decodedOrdonnances = jsonDecode(response.body);
      final ordonnanceValues = decodedOrdonnances is Map<String, dynamic>
          ? decodedOrdonnances['data'] ?? decodedOrdonnances['items'] ?? []
          : decodedOrdonnances;
      final rawOrdonnances = ordonnanceValues is List
          ? ordonnanceValues.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      final patientsResponse = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
        headers: _headers,
      );
      final decodedPatients = patientsResponse.statusCode == 200
          ? jsonDecode(patientsResponse.body)
          : const <dynamic>[];
      final patientValues = decodedPatients is Map<String, dynamic>
          ? decodedPatients['data'] ?? decodedPatients['items'] ?? []
          : decodedPatients;
      final patients = patientValues is List
          ? patientValues.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      final patientsById = {
        for (final patient in patients) patient['id'].toString(): patient,
      };
      final ordonnances = rawOrdonnances.map((ordonnance) {
        final patient = patientsById[ordonnance['patient_id']?.toString()];
        return {
          ...ordonnance,
          ...?patient == null
              ? null
              : {
                  'patient': patient,
                  'patient_nom': patient['nom'],
                  'patient_prenom': patient['prenom'],
                },
        };
      }).toList();
      for (final ordonnance in ordonnances) {
        final lines = (ordonnance['lignes'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();
        await LocalDatabase.instance.saveOrdonnanceWithLines(ordonnance, lines);
      }
      return ordonnances;
    } catch (_) {
      List<Map<String, dynamic>> local;
      try {
        local = await LocalDatabase.instance.getOrdonnances();
      } catch (_) {
        local = const [];
      }
      final filteredLocal = widget.patientId == null
          ? local
          : local
                .where(
                  (ordonnance) =>
                      ordonnance['patient_id']?.toString() == widget.patientId,
                )
                .toList();
      if (filteredLocal.isNotEmpty || widget.patientId != null) {
        List<Map<String, dynamic>> patients;
        try {
          patients = await LocalDatabase.instance.getPatients();
        } catch (_) {
          patients = const [];
        }
        final patientsById = {
          for (final patient in patients) patient['id'].toString(): patient,
        };
        return filteredLocal.map((ordonnance) {
          final patient = patientsById[ordonnance['patient_id']?.toString()];
          return {
            ...ordonnance,
            ...?patient == null
                ? null
                : {
                    'patient': patient,
                    'patient_nom': patient['nom'],
                    'patient_prenom': patient['prenom'],
                  },
          };
        }).toList();
      }
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadConsultations() async {
    return LocalDatabase.instance.getConsultations();
  }

  Future<void> createLegacy() async {
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

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewPrescriptionPage(token: widget.token),
      ),
    );
    if (created == true && mounted) setState(() => _future = _load());
  }

  Future<void> _downloadAndShare(Map<String, dynamic> prescription) async {
    final patient =
        (prescription['patient'] as Map<String, dynamic>?) ??
        <String, dynamic>{
          'nom': prescription['patient_nom'] ?? '',
          'prenom': prescription['patient_prenom'] ?? '',
        };
    try {
      final path = await downloadPrescriptionPdf(
        baseUrl: _LoginPageState._apiBaseUrl,
        token: widget.token,
        prescriptionId: prescription['id'].toString(),
      );
      await sharePrescriptionPdf(path);
    } catch (_) {
      try {
        final doctor =
            (prescription['medecin'] as Map<String, dynamic>?) ??
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Téléchargement impossible : $error')),
          );
        }
      }
    }
  }

  Future<void> _preview(Map<String, dynamic> prescription) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrescriptionPreviewPage(
          token: widget.token,
          prescription: prescription,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F8),
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: [
                const Text(
                  'Gestion médicale',
                  style: TextStyle(color: Color(0xFF547080), fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.canCreate ? 'Ordonnances' : 'Mes ordonnances',
                  style: TextStyle(
                    color: Color(0xFF06263A),
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vos prescriptions et traitements seront disponibles ici.',
                  style: TextStyle(color: Color(0xFF547080), fontSize: 16),
                ),
                if (widget.canCreate) ...[
                  const SizedBox(height: 28),
                  _NewPrescriptionButton(onPressed: _create),
                ],
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: [
                const Text(
                  'Documents médicaux',
                  style: TextStyle(color: Color(0xFF547080), fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.canCreate ? 'Ordonnances' : 'Mes ordonnances',
                  style: const TextStyle(
                    color: Color(0xFF06263A),
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Créez, consultez et téléchargez vos ordonnances.',
                  style: const TextStyle(
                    color: Color(0xFF547080),
                    fontSize: 16,
                  ),
                ),
                if (widget.canCreate) ...[
                  const SizedBox(height: 28),
                  _NewPrescriptionButton(onPressed: _create),
                ],
                const SizedBox(height: 28),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Rechercher une ordonnance',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD6E1E2)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Toutes les dates',
                          style: TextStyle(
                            color: Color(0xFF547080),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Color(0xFF547080)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                ...prescriptions
                    .where((prescription) {
                      final query = _searchController.text.trim().toLowerCase();
                      if (query.isEmpty) return true;
                      final patient =
                          '${prescription['patient_prenom'] ?? ''} ${prescription['patient_nom'] ?? ''}';
                      final lines =
                          (prescription['lignes'] as List<dynamic>? ?? [])
                              .map(
                                (line) => line is Map ? line['medicament'] : '',
                              )
                              .join(' ');
                      return '$patient $lines'.toLowerCase().contains(query);
                    })
                    .map((prescription) {
                      final lines =
                          (prescription['lignes'] as List<dynamic>? ?? []);
                      final medicine = lines.isEmpty
                          ? 'Aucun médicament'
                          : (lines.first as Map<String, dynamic>)['medicament']
                                .toString();
                      final patient =
                          (prescription['patient'] as Map<String, dynamic>?) ??
                          <String, dynamic>{
                            'nom': prescription['patient_nom'] ?? '',
                            'prenom': prescription['patient_prenom'] ?? '',
                          };
                      final patientName =
                          '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'
                              .trim();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFD6E1E2)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1206273A),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5F5F5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.description_outlined,
                                color: Color(0xFF087F88),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    medicine,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF06263A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '$patientName · ${prescription['date_emission'] ?? ''}',
                                    style: const TextStyle(
                                      color: Color(0xFF547080),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Médecin : ${prescription['medecin_nom'] ?? 'Médecin non renseigné'}',
                                    style: const TextStyle(
                                      color: Color(0xFF547080),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE2F3EF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: const Text(
                                          'Disponible',
                                          style: TextStyle(
                                            color: Color(0xFF249B86),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _downloadAndShare(prescription),
                                        icon: const Icon(
                                          Icons.download_outlined,
                                        ),
                                        label: const Text('Télécharger'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF087F88,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFD6E1E2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'aperçu') _preview(prescription);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'aperçu',
                                  child: Text('Voir l’aperçu'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        /*
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD6F0F1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.receipt_long_outlined,
                                color: Color(0xFF087F9F),
                                size: 27,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    medicine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF06263A),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    patientName.isEmpty
                                        ? 'Patient non renseigné'
                                        : patientName,
                                    style: const TextStyle(
                                      color: Color(0xFF547080),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${lines.length} médicament(s) · Émise le ${prescription['date_emission']}',
                                    style: const TextStyle(
                                      color: Color(0xFF547080),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _preview(prescription),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Aperçu'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF087F88),
                                  side: const BorderSide(
                                    color: Color(0xFFD6E1E2),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _downloadAndShare(prescription),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Télécharger'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF087F88),
                                  side: const BorderSide(
                                    color: Color(0xFFD6E1E2),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),*/
                      );
                    }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NewPrescriptionButton extends StatelessWidget {
  const _NewPrescriptionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 22),
      label: const Text('Créer une ordonnance'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        backgroundColor: const Color(0xFF087F88),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class NewPrescriptionPage extends StatefulWidget {
  const NewPrescriptionPage({super.key, required this.token});

  final String token;

  @override
  State<NewPrescriptionPage> createState() => _NewPrescriptionPageState();
}

class _NewPrescriptionPageState extends State<NewPrescriptionPage> {
  final _formKey = GlobalKey<FormState>();
  final _medicine = TextEditingController();
  final _dosage = TextEditingController();
  final _frequency = TextEditingController();
  final _duration = TextEditingController();
  final _instructions = TextEditingController();
  late Future<List<Map<String, dynamic>>> _consultations;
  String? _consultationId;
  String? _patientId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _consultations = LocalDatabase.instance.getConsultations();
  }

  @override
  void dispose() {
    for (final controller in [
      _medicine,
      _dosage,
      _frequency,
      _duration,
      _instructions,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _consultationId == null ||
        _patientId == null) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final line = <String, dynamic>{
      'id': const Uuid().v4(),
      'medicament': _medicine.text.trim(),
      'dosage': _dosage.text.trim(),
      'frequence': _frequency.text.trim(),
      'duree': _duration.text.trim(),
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
      'is_deleted': false,
    };
    final consultation = (await LocalDatabase.instance.getConsultations())
        .firstWhere(
          (item) => item['id']?.toString() == _consultationId,
          orElse: () => <String, dynamic>{},
        );
    final payload = <String, dynamic>{
      'id': const Uuid().v4(),
      'consultation_id': _consultationId,
      'patient_id': _patientId,
      'medecin_id': consultation['medecin_id']?.toString(),
      'date_emission': now.substring(0, 10),
      'instructions_generales': _instructions.text.trim(),
      'lignes': [line],
      'sync_status': 'pending',
      'created_at': now,
      'updated_at': now,
      'is_deleted': false,
    };
    setState(() => _saving = true);
    try {
      final operationId = await LocalDatabase.instance.addPendingOperation(
        entity: 'ordonnance',
        entityId: payload['id'] as String,
        operation: 'upsert',
        payload: payload,
      );
      await LocalDatabase.instance.saveOrdonnanceWithLines(payload, [line]);
      try {
        await SyncService(
          baseUrl: _LoginPageState._apiBaseUrl,
          token: widget.token,
        ).syncPendingOrdonnances();
        await LocalDatabase.instance.removePendingOperation(operationId);
      } catch (_) {}
      if (mounted) {
        Navigator.pop(context, true);
      }
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F8F8),
    appBar: AppBar(
      title: const Text('Nouvelle ordonnance'),
      automaticallyImplyLeading: false,
      backgroundColor: const Color(0xFFF3F8F8),
      foregroundColor: const Color(0xFF06263A),
      elevation: 0,
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _consultations,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final consultations = snapshot.data ?? const <Map<String, dynamic>>[];
        if (consultations.isEmpty) {
          return const Center(child: Text('Créez d’abord une consultation.'));
        }
        _consultationId ??= consultations.first['id']?.toString();
        _patientId ??= consultations.first['patient_id']?.toString();
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [
              const Text(
                'Nouvelle ordonnance',
                style: TextStyle(
                  color: Color(0xFF06263A),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Prescrivez un traitement et préparez le document PDF du patient.',
                style: TextStyle(color: Color(0xFF547080), fontSize: 15),
              ),
              const SizedBox(height: 22),
              _PrescriptionFormCard(
                children: [
                  const Text(
                    'Consultation liée',
                    style: TextStyle(
                      color: Color(0xFF06263A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _consultationId,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.medical_information_outlined),
                    ),
                    items: consultations
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['id']?.toString(),
                            child: Text(
                              item['motif']?.toString() ?? 'Consultation',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      final selected = consultations.firstWhere(
                        (item) => item['id']?.toString() == value,
                      );
                      setState(() {
                        _consultationId = value;
                        _patientId = selected['patient_id']?.toString();
                      });
                    },
                  ),
                  _PrescriptionField(
                    label: 'Médicament *',
                    controller: _medicine,
                    icon: Icons.medication_outlined,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Le médicament est obligatoire'
                        : null,
                  ),
                  _PrescriptionField(
                    label: 'Dosage',
                    controller: _dosage,
                    icon: Icons.science_outlined,
                  ),
                  _PrescriptionField(
                    label: 'Fréquence',
                    controller: _frequency,
                    icon: Icons.schedule_outlined,
                  ),
                  _PrescriptionField(
                    label: 'Durée',
                    controller: _duration,
                    icon: Icons.timelapse_outlined,
                  ),
                  _PrescriptionField(
                    label: 'Instructions générales',
                    controller: _instructions,
                    icon: Icons.notes_outlined,
                    maxLines: 4,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    _saving ? 'Enregistrement...' : 'Créer l’ordonnance',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _PrescriptionFormCard extends StatelessWidget {
  const _PrescriptionFormCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD6E1E2)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1206273A),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _PrescriptionField extends StatelessWidget {
  const _PrescriptionField({
    required this.label,
    required this.controller,
    required this.icon,
    this.validator,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? Function(String?)? validator;
  final int maxLines;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    ),
  );
}

class PrescriptionPreviewPage extends StatelessWidget {
  const PrescriptionPreviewPage({
    super.key,
    required this.token,
    required this.prescription,
  });
  final String token;
  final Map<String, dynamic> prescription;

  Future<void> _download(BuildContext context) async {
    final patient =
        (prescription['patient'] as Map<String, dynamic>?) ??
        {
          'nom': prescription['patient_nom'] ?? '',
          'prenom': prescription['patient_prenom'] ?? '',
        };
    try {
      final path = await downloadPrescriptionPdf(
        baseUrl: _LoginPageState._apiBaseUrl,
        token: token,
        prescriptionId: prescription['id'].toString(),
      );
      await sharePrescriptionPdf(path);
    } catch (_) {
      final path = await exportPrescriptionPdf(
        prescription: prescription,
        patient: patient,
        doctor: {
          'nom': prescription['medecin_nom'] ?? 'Médecin',
          'specialite': prescription['specialite'],
        },
      );
      await sharePrescriptionPdf(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = (prescription['lignes'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final patient =
        (prescription['patient'] as Map<String, dynamic>?) ??
        {
          'nom': prescription['patient_nom'] ?? '',
          'prenom': prescription['patient_prenom'] ?? '',
        };
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F8),
      appBar: AppBar(
        title: const Text('Aperçu ordonnance'),
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF3F8F8),
        foregroundColor: const Color(0xFF06263A),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD6E1E2)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1206273A),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ROVA',
                  style: TextStyle(
                    color: Color(0xFF087F88),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ORDONNANCE',
                  style: TextStyle(
                    color: Color(0xFF06263A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Divider(height: 28),
                Text(
                  'Patient : ${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}',
                  style: const TextStyle(
                    color: Color(0xFF06263A),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                ...lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.medication_outlined,
                          color: Color(0xFF087F88),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line['medicament']?.toString() ?? 'Médicament',
                                style: const TextStyle(
                                  color: Color(0xFF06263A),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${line['dosage'] ?? ''} · ${line['frequence'] ?? ''} · ${line['duree'] ?? ''}',
                                style: const TextStyle(
                                  color: Color(0xFF547080),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if ((prescription['instructions_generales']?.toString() ?? '')
                    .isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    prescription['instructions_generales'].toString(),
                    style: const TextStyle(
                      color: Color(0xFF547080),
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _download(context),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Télécharger / partager le PDF'),
            ),
          ),
        ],
      ),
    );
  }
}
