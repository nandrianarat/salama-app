part of '../main.dart';

/// Patients feature entry point.
///
/// The data loading, offline fallback and patient cards remain in the legacy
/// implementation for now; this page is the stable place to replace its UI.
class PatientsFeaturePage extends StatelessWidget {
  const PatientsFeaturePage({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) => PatientsPage(token: token);
}

class PatientFormPage extends StatelessWidget {
  const PatientFormPage({super.key, required this.token, this.patient});

  final String token;
  final Map<String, dynamic>? patient;

  @override
  Widget build(BuildContext context) =>
      _PatientFormScreen(token: token, patient: patient);
}

class _PatientFormScreen extends StatefulWidget {
  const _PatientFormScreen({required this.token, this.patient});

  final String token;
  final Map<String, dynamic>? patient;

  @override
  State<_PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<_PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nom = TextEditingController();
  final _prenom = TextEditingController();
  final _telephone = TextEditingController();
  final _adresse = TextEditingController();
  final _allergies = TextEditingController();
  final _urgence = TextEditingController();
  DateTime? _dateNaissance;
  String? _sexe;
  String? _groupeSanguin;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [
      _nom,
      _prenom,
      _telephone,
      _adresse,
      _allergies,
      _urgence,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().length < 2 ? 'Minimum 2 caractères' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = widget.patient?['id']?.toString() ?? const Uuid().v4();
    final payload = <String, dynamic>{
      'id': id,
      'nom': _nom.text.trim(),
      'prenom': _prenom.text.trim(),
      'telephone': _optional(_telephone.text),
      'date_naissance': _dateNaissance?.toIso8601String().substring(0, 10),
      'sexe': _sexe,
      'adresse': _optional(_adresse.text),
      'groupe_sanguin': _groupeSanguin,
      'allergies': _optional(_allergies.text),
      'contact_urgence': _optional(_urgence.text),
      'created_at': now,
      'updated_at': now,
      'sync_status': widget.patient == null ? 'pending' : 'updated',
      'is_deleted': false,
    };

    setState(() => _saving = true);
    setState(() => _saving = true);
    try {
      final response = await http.request(
        Uri.parse(
          widget.patient == null
              ? '${_LoginPageState._apiBaseUrl}/api/v1/patients'
              : '${_LoginPageState._apiBaseUrl}/api/v1/patients/$id',
        ),
        widget.patient == null ? 'POST' : 'PUT',
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await LocalDatabase.instance.savePatient(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else {
        throw Exception('Erreur serveur (${response.statusCode})');
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

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _AdminColors.background,
    appBar: AppBar(
      title: Text(
        widget.patient == null ? 'Nouveau patient' : 'Modifier le patient',
      ),
      backgroundColor: _AdminColors.background,
      foregroundColor: _AdminColors.text,
      elevation: 0,
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          const _FormIntro(
            eyebrow: 'Dossier médical',
            title: 'Nouveau patient',
            description: 'Renseignez les informations essentielles du dossier.',
          ),
          const SizedBox(height: 24),
          const _FormSectionTitle(
            title: 'Identité',
            subtitle: 'Les champs marqués d’un astérisque sont obligatoires.',
          ),
          _field(_nom, 'Nom *', Icons.badge_outlined, validator: _required),
          _field(
            _prenom,
            'Prénom *',
            Icons.person_outline,
            validator: _required,
          ),
          _field(
            _telephone,
            'Téléphone',
            Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime(1900),
                lastDate: DateTime.now(),
                initialDate: _dateNaissance ?? DateTime(1990),
              );
              if (date != null) setState(() => _dateNaissance = date);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date de naissance',
                prefixIcon: Icon(Icons.cake_outlined),
              ),
              child: Text(
                _dateNaissance == null
                    ? 'Sélectionner une date'
                    : MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(_dateNaissance!),
              ),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                DropdownButtonFormField<String>(
                  initialValue: _sexe,
                  decoration: const InputDecoration(
                    labelText: 'Sexe',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'F', child: Text('Femme')),
                    DropdownMenuItem(value: 'M', child: Text('Homme')),
                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                  ],
                  onChanged: (value) => setState(() => _sexe = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _groupeSanguin,
                  decoration: const InputDecoration(
                    labelText: 'Groupe sanguin',
                    prefixIcon: Icon(Icons.bloodtype_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'A+', child: Text('A+')),
                    DropdownMenuItem(value: 'A-', child: Text('A-')),
                    DropdownMenuItem(value: 'B+', child: Text('B+')),
                    DropdownMenuItem(value: 'B-', child: Text('B-')),
                    DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                    DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                    DropdownMenuItem(value: 'O+', child: Text('O+')),
                    DropdownMenuItem(value: 'O-', child: Text('O-')),
                  ],
                  onChanged: (value) => setState(() => _groupeSanguin = value),
                ),
              ];
              return constraints.maxWidth < 430
                  ? Column(
                      children: [
                        fields[0],
                        const SizedBox(height: 14),
                        fields[1],
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),
          const _FormSectionTitle(
            title: 'Informations complémentaires',
            subtitle: 'Facultatives, mais utiles au suivi médical.',
          ),
          _field(_adresse, 'Adresse', Icons.location_on_outlined, maxLines: 2),
          _field(
            _allergies,
            'Allergies connues',
            Icons.warning_amber_outlined,
            maxLines: 2,
          ),
          _field(
            _urgence,
            'Contact d’urgence',
            Icons.contact_phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    ),
  );
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
    final patient = widget.patient;
    if (patient != null) {
      _nom.text = patient['nom']?.toString() ?? '';
      _prenom.text = patient['prenom']?.toString() ?? '';
      _telephone.text = patient['telephone']?.toString() ?? '';
      _adresse.text = patient['adresse']?.toString() ?? '';
      _allergies.text = patient['allergies']?.toString() ?? '';
      _urgence.text = patient['contact_urgence']?.toString() ?? '';
      _dateNaissance = DateTime.tryParse(
        patient['date_naissance']?.toString() ?? '',
      );
      _sexe = patient['sexe']?.toString();
      _groupeSanguin = patient['groupe_sanguin']?.toString();
    }
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
      backgroundColor: _AdminColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              setState(() => _patientsFuture = _loadPatients()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Patients',
                      style: const TextStyle(
                        color: _AdminColors.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final created = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientFormPage(token: widget.token),
                        ),
                      );
                      if (created == true && mounted) {
                        setState(() => _patientsFuture = _loadPatients());
                      }
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Nouveau'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) =>
                    setState(() => _patientsFuture = _loadPatients(value)),
                decoration: InputDecoration(
                  hintText: 'Rechercher un patient',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Effacer la recherche',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _patientsFuture = _loadPatients());
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _patientsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Impossible de charger les patients.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: HadText.body.copyWith(
                            color: HadColors.inkSoft,
                          ),
                        ),
                      ),
                    );
                  }

                  final patients = snapshot.data ?? [];
                  if (patients.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.people_alt_outlined,
                              size: 40,
                              color: HadColors.inkSoft,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Aucun patient enregistré',
                              style: HadText.sectionTitle,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      for (final patient in patients)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientRecordPage(
                                    patient: patient,
                                    token: widget.token,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: HadColors.sageSoft,
                                      child: Text(
                                        _patientInitials(patient),
                                        style: const TextStyle(
                                          color: HadColors.ink,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'
                                                .trim(),
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: HadColors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            patient['telephone']?.toString() ??
                                                'Téléphone non renseigné',
                                            style: const TextStyle(
                                              color: HadColors.inkSoft,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              _InfoPill(
                                                label: 'Sexe',
                                                value:
                                                    (patient['sexe'] ??
                                                            'Non défini')
                                                        .toString(),
                                              ),
                                              _InfoPill(
                                                label: 'Naissance',
                                                value: _formatDate(
                                                  patient['date_naissance'],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right_rounded,
                                      color: HadColors.inkSoft,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _patientInitials(Map<String, dynamic> patient) {
    final parts = [
      patient['prenom']?.toString() ?? '',
      patient['nom']?.toString() ?? '',
    ].where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'P';
    return parts
        .map((part) => part.trim().substring(0, 1).toUpperCase())
        .take(2)
        .join();
  }

  String _formatDate(Object? value) {
    if (value == null || value.toString().isEmpty) return 'Non défini';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class PatientDetailsPage extends StatelessWidget {
  const PatientDetailsPage({
    super.key,
    required this.patient,
    required this.token,
  });

  final Map<String, dynamic> patient;
  final String token;

  @override
  Widget build(BuildContext context) {
    final name = '${patient['prenom']} ${patient['nom']}'.trim();
    return Scaffold(
      backgroundColor: _AdminColors.background,
      appBar: AppBar(
        title: const Text('Dossier patient'),
        backgroundColor: _AdminColors.background,
        foregroundColor: _AdminColors.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: HadColors.sageSoft,
                        child: Text(
                          _patientInitials(patient),
                          style: const TextStyle(
                            color: HadColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                color: HadColors.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('Fiche patient', style: HadText.bodySoft),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.1,
                    children: [
                      _MetricTile(
                        icon: Icons.phone_outlined,
                        label: 'Téléphone',
                        value:
                            patient['telephone']?.toString() ?? 'Non renseigné',
                      ),
                      _MetricTile(
                        icon: Icons.cake_outlined,
                        label: 'Naissance',
                        value:
                            patient['date_naissance']?.toString() ??
                            'Non renseignée',
                      ),
                      _MetricTile(
                        icon: Icons.bloodtype_outlined,
                        label: 'Groupe',
                        value:
                            patient['groupe_sanguin']?.toString() ??
                            'Non renseigné',
                      ),
                      _MetricTile(
                        icon: Icons.person_outline,
                        label: 'Sexe',
                        value: patient['sexe']?.toString() ?? 'Non défini',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _PatientDetailRow(
                    icon: Icons.location_on_outlined,
                    label: 'Adresse',
                    value: patient['adresse']?.toString() ?? 'Non renseignée',
                  ),
                  _PatientDetailRow(
                    icon: Icons.warning_amber_outlined,
                    label: 'Allergies',
                    value: patient['allergies']?.toString() ?? 'Aucune connue',
                    color: const Color(0xFFD8485E),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConsultationFormPage(
                        token: token,
                        initialPatientId: patient['id']?.toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Consultation'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrescriptionsPage(
                        token: token,
                        patientId: patient['id']?.toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ordonnances'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Historique', style: HadText.sectionTitle),
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucune consultation enregistrée pour ce patient pour le moment.',
                style: TextStyle(color: HadColors.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _patientInitials(Map<String, dynamic> patient) {
    final parts = [
      patient['prenom']?.toString() ?? '',
      patient['nom']?.toString() ?? '',
    ].where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return 'P';
    return parts
        .map((part) => part.trim().substring(0, 1).toUpperCase())
        .take(2)
        .join();
  }
}

class PatientRecordPage extends StatefulWidget {
  const PatientRecordPage({
    super.key,
    required this.patient,
    required this.token,
  });

  final Map<String, dynamic> patient;
  final String token;

  @override
  State<PatientRecordPage> createState() => _PatientRecordPageState();
}

class _PatientRecordPageState extends State<PatientRecordPage> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final records = await LocalDatabase.instance.getConsultations();
    final id = widget.patient['id']?.toString();
    return records
        .where((record) => record['patient_id']?.toString() == id)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final name = '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    return Scaffold(
      backgroundColor: _AdminColors.background,
      appBar: AppBar(
        title: const Text('Dossier patient'),
        backgroundColor: _AdminColors.background,
        foregroundColor: _AdminColors.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _AdminColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: _AdminColors.tealSoft,
                      child: Text(
                        _recordInitials(patient),
                        style: const TextStyle(
                          color: _AdminColors.teal,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: _AdminColors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Dossier médical et suivi clinique',
                            style: TextStyle(color: _AdminColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _RecordPill(
                      icon: Icons.phone_outlined,
                      value:
                          patient['telephone']?.toString() ??
                          'Téléphone non renseigné',
                    ),
                    _RecordPill(
                      icon: Icons.bloodtype_outlined,
                      value:
                          patient['groupe_sanguin']?.toString() ??
                          'Groupe non renseigné',
                    ),
                    _RecordPill(
                      icon: Icons.person_outline,
                      value: patient['sexe']?.toString() ?? 'Sexe non défini',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _RecordLine(
                  label: 'Adresse',
                  value: patient['adresse']?.toString() ?? 'Non renseignée',
                  icon: Icons.location_on_outlined,
                ),
                _RecordLine(
                  label: 'Allergies',
                  value: patient['allergies']?.toString() ?? 'Aucune connue',
                  icon: Icons.warning_amber_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConsultationFormPage(
                        token: widget.token,
                        initialPatientId: patient['id']?.toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Consultation'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrescriptionsPage(
                        token: widget.token,
                        patientId: patient['id']?.toString(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ordonnances'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Historique des consultations',
            style: TextStyle(
              color: _AdminColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final history = snapshot.data ?? const <Map<String, dynamic>>[];
              if (history.isEmpty) return const _PatientRecordEmpty();
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _AdminColors.border),
                ),
                child: Column(
                  children: history.map((record) {
                    final date = DateTime.tryParse(
                      record['date']?.toString() ?? '',
                    );
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: _AdminColors.tealSoft,
                        child: Icon(
                          Icons.medical_information_outlined,
                          color: _AdminColors.teal,
                        ),
                      ),
                      title: Text(
                        record['motif']?.toString() ?? 'Consultation',
                        style: const TextStyle(
                          color: _AdminColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        '${date == null ? 'Date non renseignée' : MaterialLocalizations.of(context).formatFullDate(date)} · ${_recordLocation(record)}',
                        style: const TextStyle(color: _AdminColors.muted),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecordPill extends StatelessWidget {
  const _RecordPill({required this.icon, required this.value});
  final IconData icon;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: _AdminColors.tealSoft,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: _AdminColors.teal),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            color: _AdminColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _RecordLine extends StatelessWidget {
  const _RecordLine({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _AdminColors.muted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$label : $value',
            style: const TextStyle(color: _AdminColors.muted, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _PatientRecordEmpty extends StatelessWidget {
  const _PatientRecordEmpty();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
    ),
    child: const Text(
      'Aucune consultation enregistrée pour ce patient.',
      style: TextStyle(color: _AdminColors.muted),
    ),
  );
}

String _recordInitials(Map<String, dynamic> patient) {
  final values = [patient['prenom'], patient['nom']]
      .where((value) => value != null && value.toString().trim().isNotEmpty)
      .map((value) => value.toString().trim()[0].toUpperCase())
      .take(2);
  return values.join();
}

String _recordLocation(Map<String, dynamic> record) {
  if (record['lieu'] == 'Domicile') return 'Domicile';
  return (record['notes']?.toString() ?? '').startsWith('Lieu: Domicile')
      ? 'Domicile'
      : 'Cabinet';
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _AdminColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: HadColors.sageSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: HadColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: HadText.bodySoft),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: HadColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: HadColors.cream,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: HadColors.border),
    ),
    child: Text(
      '$label : $value',
      style: const TextStyle(
        fontSize: 10,
        color: HadColors.ink,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _PatientDetailRow extends StatelessWidget {
  const _PatientDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color ?? const Color(0xFF087F9F)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF9AA8B8), fontSize: 10),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
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
  final _adresseController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _urgenceController = TextEditingController();
  DateTime? _dateNaissance;
  String? _sexe;
  String? _groupeSanguin;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _telephoneController.dispose();
    _adresseController.dispose();
    _allergiesController.dispose();
    _urgenceController.dispose();
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
      'date_naissance': _dateNaissance?.toIso8601String().substring(0, 10),
      'sexe': _sexe,
      'adresse': _adresseController.text.trim().isEmpty
          ? null
          : _adresseController.text.trim(),
      'groupe_sanguin': _groupeSanguin,
      'allergies': _allergiesController.text.trim().isEmpty
          ? null
          : _allergiesController.text.trim(),
      'contact_urgence': _urgenceController.text.trim().isEmpty
          ? null
          : _urgenceController.text.trim(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
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
      backgroundColor: _AdminColors.background,
      appBar: AppBar(
        title: const Text('Nouveau patient'),
        backgroundColor: _AdminColors.background,
        foregroundColor: _AdminColors.text,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            const _FormIntro(
              eyebrow: 'Dossier médical',
              title: 'Nouveau patient',
              description:
                  'Renseignez les informations essentielles du dossier.',
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle(
              title: 'Identité',
              subtitle:
                  'Ces informations permettent de retrouver rapidement le dossier.',
            ),
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
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                  initialDate: _dateNaissance ?? DateTime(1990),
                );
                if (date != null) setState(() => _dateNaissance = date);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date de naissance',
                  prefixIcon: Icon(Icons.cake_outlined),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _dateNaissance == null
                      ? 'Sélectionner une date'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_dateNaissance!),
                  style: TextStyle(
                    color: _dateNaissance == null ? Colors.grey : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 430;
                final sexe = DropdownButtonFormField<String>(
                  initialValue: _sexe,
                  decoration: const InputDecoration(
                    labelText: 'Sexe',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'F', child: Text('Femme')),
                    DropdownMenuItem(value: 'M', child: Text('Homme')),
                    DropdownMenuItem(value: 'autre', child: Text('Autre')),
                  ],
                  onChanged: (value) => setState(() => _sexe = value),
                );
                final groupe = DropdownButtonFormField<String>(
                  initialValue: _groupeSanguin,
                  decoration: const InputDecoration(
                    labelText: 'Groupe sanguin',
                    prefixIcon: Icon(Icons.bloodtype_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'A+', child: Text('A+')),
                    DropdownMenuItem(value: 'A-', child: Text('A-')),
                    DropdownMenuItem(value: 'B+', child: Text('B+')),
                    DropdownMenuItem(value: 'B-', child: Text('B-')),
                    DropdownMenuItem(value: 'AB+', child: Text('AB+')),
                    DropdownMenuItem(value: 'AB-', child: Text('AB-')),
                    DropdownMenuItem(value: 'O+', child: Text('O+')),
                    DropdownMenuItem(value: 'O-', child: Text('O-')),
                  ],
                  onChanged: (value) => setState(() => _groupeSanguin = value),
                );
                return narrow
                    ? Column(
                        children: [sexe, const SizedBox(height: 14), groupe],
                      )
                    : Row(
                        children: [
                          Expanded(child: sexe),
                          const SizedBox(width: 12),
                          Expanded(child: groupe),
                        ],
                      );
              },
            ),
            const SizedBox(height: 24),
            const _FormSectionTitle(
              title: 'Informations complémentaires',
              subtitle:
                  'Facultatives, mais utiles pour assurer un meilleur suivi.',
            ),
            TextFormField(
              controller: _adresseController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Adresse',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _allergiesController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Allergies connues',
                hintText: 'Ex. Pénicilline, arachide...',
                prefixIcon: Icon(Icons.warning_amber_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _urgenceController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact d’urgence',
                prefixIcon: Icon(Icons.contact_phone_outlined),
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
