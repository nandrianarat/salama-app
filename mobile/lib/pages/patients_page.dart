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
  const PatientFormPage({
    super.key,
    required this.token,
    this.patient,
    this.role,
  });

  final String token;
  final Map<String, dynamic>? patient;
  final String? role;

  @override
  Widget build(BuildContext context) =>
      _PatientFormScreen(token: token, patient: patient, role: role);
}

class _PatientFormScreen extends StatefulWidget {
  const _PatientFormScreen({required this.token, this.patient, this.role});

  final String token;
  final Map<String, dynamic>? patient;
  final String? role;

  bool get isAdministrativeOnly => role?.toLowerCase() == 'secretaire';

  @override
  State<_PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<_PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _prenom = TextEditingController();
  final _telephone = TextEditingController();
  final _adresse = TextEditingController();
  final _allergies = TextEditingController();
  final _urgence = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  DateTime? _dateNaissance;
  String? _sexe;
  String? _groupeSanguin;
  bool _saving = false;

  bool get _isEditing => widget.patient != null;

  @override
  void initState() {
    super.initState();
    final patient = widget.patient;
    if (patient == null) return;
    _prenom.text = '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    _telephone.text = (patient['telephone'] ?? '').toString();
    _adresse.text = (patient['adresse'] ?? '').toString();
    _allergies.text = (patient['allergies'] ?? '').toString();
    _urgence.text = (patient['contact_urgence'] ?? '').toString();
    _sexe = patient['sexe']?.toString();
    _groupeSanguin = patient['groupe_sanguin']?.toString();
    final dateValue = patient['date_naissance']?.toString();
    if (dateValue != null && dateValue.isNotEmpty) {
      _dateNaissance = DateTime.tryParse(dateValue);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _prenom,
      _telephone,
      _adresse,
      _allergies,
      _urgence,
      _login,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().length < 2 ? 'Minimum 2 caractères' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    final patientId = widget.patient?['id']?.toString() ?? const Uuid().v4();
    final fullName = _prenom.text.trim();
    final nameParts = fullName.split(RegExp(r'\s+'));
    final lastName = nameParts.length > 1 ? nameParts.removeLast() : fullName;
    final payload = <String, dynamic>{
      'nom': lastName,
      'prenom': nameParts.join(' ').trim().isEmpty
          ? lastName
          : nameParts.join(' ').trim(),
      'telephone': _optional(_telephone.text),
      'date_naissance': _dateNaissance?.toIso8601String().substring(0, 10),
      'sexe': _sexe,
      'adresse': _optional(_adresse.text),
      'contact_urgence': _optional(_urgence.text),
    };
    if (!widget.isAdministrativeOnly) {
      payload['groupe_sanguin'] = _groupeSanguin;
      payload['allergies'] = _optional(_allergies.text);
    }
    if (!_isEditing) {
      final login = _login.text.trim();
      final password = _password.text;
      if (login.length < 3 || password.length < 6) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Identifiant et mot de passe patient obligatoires.'),
          ),
        );
        return;
      }
      payload['login'] = login;
      payload['mot_de_passe'] = password;
    }

    setState(() => _saving = true);
    try {
      final isPatient = widget.role?.toLowerCase() == 'patient';
      final uri = Uri.parse(
        isPatient
            ? '${_LoginPageState._apiBaseUrl}/api/v1/me/patient'
            : '${_LoginPageState._apiBaseUrl}/api/v1/patients${_isEditing ? '/$patientId' : ''}',
      );
      final response = await (_isEditing
          ? http.put(
              uri,
              headers: {
                'Authorization': 'Bearer ${widget.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
          : http.post(
              uri,
              headers: {
                'Authorization': 'Bearer ${widget.token}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({...payload, 'id': patientId}),
            ));

      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
        await LocalDatabase.instance.savePatient(responseBody);
        if (mounted) navigator.pop(true);
        return;
      }

      throw Exception('Erreur ${(response.statusCode)} : ${response.body}');
    } catch (_) {
      if (mounted && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Impossible de modifier le patient.'
                  : 'Impossible d’ajouter le patient.',
            ),
          ),
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
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _AdminColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rova · Gestion médicale',
                  style: TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _isEditing ? 'Modifier un patient' : 'Ajouter un patient',
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isEditing
                      ? 'Mettez à jour les informations nécessaires.'
                      : 'Renseignez les informations nécessaires pour continuer.',
                  style: const TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(color: _AdminColors.border),
                ),
                _formLabel('Nom complet'),
                _field(
                  _prenom,
                  'Ex. Miora Andrianina',
                  Icons.person_outline,
                  validator: _required,
                ),
                if (!_isEditing) ...[
                  _formLabel('Identifiant du patient'),
                  _field(
                    _login,
                    'Ex. tovo.rakoto',
                    Icons.account_circle_outlined,
                  ),
                  _formLabel('Mot de passe temporaire'),
                  _field(
                    _password,
                    '6 caractères minimum',
                    Icons.lock_outline,
                    obscureText: true,
                  ),
                ],
                _formLabel('Téléphone'),
                _field(
                  _telephone,
                  '+261 34 00 000 00',
                  Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                _formLabel('Date de naissance'),
                _birthDateField(),
                _formLabel('Adresse'),
                _field(
                  _adresse,
                  'Ville, quartier',
                  Icons.location_on_outlined,
                  maxLines: 2,
                ),
                if (!widget.isAdministrativeOnly) ...[
                  _formLabel('Groupe sanguin'),
                  _bloodGroupField(),
                ],
                _formLabel("Contact d'urgence"),
                _field(
                  _urgence,
                  'Nom et téléphone',
                  Icons.contact_phone_outlined,
                ),
                if (!widget.isAdministrativeOnly) ...[
                  _formLabel('Allergies connues'),
                  _field(
                    _allergies,
                    'Aucune allergie connue',
                    Icons.warning_amber_outlined,
                    maxLines: 3,
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: _AdminColors.border),
                ),
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
                        : const Icon(Icons.add),
                    label: Text(_saving ? 'Enregistrement...' : 'Enregistrer'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _AdminColors.teal,
                      backgroundColor: _AdminColors.tealSoft,
                      side: BorderSide.none,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Annuler'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _formLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 10),
    child: Text(
      label,
      style: const TextStyle(
        color: _AdminColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _birthDateField() => InkWell(
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
        hintText: 'jj/mm/aaaa',
        suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
      ),
      child: Text(
        _dateNaissance == null
            ? 'jj/mm/aaaa'
            : MaterialLocalizations.of(
                context,
              ).formatMediumDate(_dateNaissance!),
      ),
    ),
  );

  Widget _bloodGroupField() => DropdownButtonFormField<String>(
    initialValue: _groupeSanguin,
    decoration: const InputDecoration(hintText: 'Sélectionner'),
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

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool obscureText = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      obscureText: obscureText,
      decoration: InputDecoration(hintText: label, prefixIcon: Icon(icon)),
    ),
  );
}

class PatientsPage extends StatefulWidget {
  const PatientsPage({super.key, required this.token, this.role});

  final String token;
  final String? role;

  @override
  State<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends State<PatientsPage> {
  late Future<List<Map<String, dynamic>>> _patientsFuture;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _patientsFuture = _loadPatients();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _searchPatients(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _patientsFuture = _loadPatients(value));
    });
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
      if (patients.isEmpty && (query == null || query.isEmpty)) {
        await LocalDatabase.instance.clearAllData();
      }
      for (final patient in patients) {
        await LocalDatabase.instance.savePatient(patient);
      }
      return patients;
    } catch (_) {
      final localPatients = await LocalDatabase.instance.getPatients(
        search: query,
      );
      if (widget.role?.toLowerCase() == 'patient') {
        return const <Map<String, dynamic>>[];
      }
      if (widget.role?.toLowerCase() == 'secretaire') {
        return localPatients.map((patient) {
          final administrative = Map<String, dynamic>.from(patient)
            ..remove('groupe_sanguin')
            ..remove('allergies');
          return administrative;
        }).toList();
      }
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
              const Text(
                'Gestion médicale',
                style: TextStyle(
                  color: _AdminColors.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Patients',
                style: TextStyle(
                  color: _AdminColors.text,
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Gérez les dossiers et le suivi de vos patients.',
                style: TextStyle(
                  color: _AdminColors.muted,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              if (widget.role?.toLowerCase() != 'patient')
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
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
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text('Ajouter un patient'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: _AdminColors.teal,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 42),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: _searchPatients,
                onSubmitted: (value) {
                  _searchDebounce?.cancel();
                  setState(() => _patientsFuture = _loadPatients(value));
                },
                decoration: InputDecoration(
                  hintText: 'Rechercher un patient...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _AdminColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _AdminColors.border),
                  ),
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
              const SizedBox(height: 16),
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _AdminColors.border),
                ),
                child: const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tous les patients',
                        style: TextStyle(
                          color: _AdminColors.muted,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: _AdminColors.muted),
                  ],
                ),
              ),
              const SizedBox(height: 28),
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

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _AdminColors.border),
                    ),
                    child: Column(
                      children: [
                        for (var index = 0; index < patients.length; index++)
                          _PatientCompactTile(
                            patient: patients[index],
                            showDivider: index < patients.length - 1,
                            onTap: () async {
                              final refreshed = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientRecordPage(
                                    patient: patients[index],
                                    token: widget.token,
                                    role: widget.role,
                                  ),
                                ),
                              );
                              if (refreshed == true && mounted) {
                                setState(
                                  () => _patientsFuture = _loadPatients(),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientCompactTile extends StatelessWidget {
  const _PatientCompactTile({
    required this.patient,
    required this.showDivider,
    required this.onTap,
  });

  final Map<String, dynamic> patient;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    final age = _patientAge(patient['date_naissance']);
    final summary = _patientSummary(patient);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFE4F3F4),
                  child: Text(
                    _compactInitials(patient),
                    style: const TextStyle(
                      color: _AdminColors.teal,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Patient' : name,
                        style: const TextStyle(
                          color: _AdminColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${age == null ? 'Âge non renseigné' : '$age ans'} ·',
                        style: const TextStyle(
                          color: _AdminColors.muted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _AdminColors.muted,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF9BAEB2),
                  size: 25,
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _AdminColors.border),
      ],
    );
  }
}

String _compactInitials(Map<String, dynamic> patient) {
  final parts = [
    patient['prenom']?.toString() ?? '',
    patient['nom']?.toString() ?? '',
  ].where((part) => part.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'P';
  return parts
      .map((part) => part.trim().substring(0, 1).toUpperCase())
      .take(2)
      .join();
}

int? _patientAge(Object? value) {
  if (value == null || value.toString().isEmpty) return null;
  final birthDate = DateTime.tryParse(value.toString());
  if (birthDate == null) return null;
  final today = DateTime.now();
  var age = today.year - birthDate.year;
  if (today.month < birthDate.month ||
      (today.month == birthDate.month && today.day < birthDate.day)) {
    age--;
  }
  return age < 0 ? null : age;
}

String _patientSummary(Map<String, dynamic> patient) {
  final allergies = patient['allergies']?.toString().trim() ?? '';
  if (allergies.isNotEmpty) return allergies;
  final bloodGroup = patient['groupe_sanguin']?.toString().trim() ?? '';
  if (bloodGroup.isNotEmpty) return 'Groupe sanguin : $bloodGroup';
  return 'Aucune allergie connue';
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
        automaticallyImplyLeading: false,
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
    this.role,
  });

  final Map<String, dynamic> patient;
  final String token;
  final String? role;

  bool get hasClinicalAccess =>
      role?.toLowerCase() == 'medecin' ||
      role?.toLowerCase() == 'infirmier' ||
      role?.toLowerCase() == 'patient';

  @override
  State<PatientRecordPage> createState() => _PatientRecordPageState();
}

class _PatientRecordPageState extends State<PatientRecordPage> {
  late Future<_PatientRecordData> _recordFuture;

  @override
  void initState() {
    super.initState();
    _recordFuture = _loadRecord();
  }

  Future<_PatientRecordData> _loadRecord() async {
    final id = widget.patient['id']?.toString() ?? '';
    final appointments = (await LocalDatabase.instance.getRendezVous())
        .where((record) => record['patient_id']?.toString() == id)
        .toList();
    final consultations = widget.hasClinicalAccess
        ? await _loadOwnConsultations(id)
        : const <Map<String, dynamic>>[];
    final prescriptions =
        widget.role?.toLowerCase() == 'medecin' ||
            widget.role?.toLowerCase() == 'patient'
        ? await _loadOwnPrescriptions(id)
        : const <Map<String, dynamic>>[];
    return _PatientRecordData(
      consultations: consultations,
      appointments: appointments,
      prescriptions: prescriptions,
    );
  }

  Future<List<Map<String, dynamic>>> _loadOwnConsultations(String id) async {
    if (widget.role?.toLowerCase() != 'patient') {
      return (await LocalDatabase.instance.getConsultations())
          .where((record) => record['patient_id']?.toString() == id)
          .toList();
    }
    final response = await http.get(
      Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/consultations'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Historique indisponible');
    }
    final records = (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    for (final record in records) {
      await LocalDatabase.instance.saveConsultation(record);
    }
    return records;
  }

  Future<List<Map<String, dynamic>>> _loadOwnPrescriptions(String id) async {
    if (widget.role?.toLowerCase() != 'patient') {
      return (await LocalDatabase.instance.getOrdonnances())
          .where((record) => record['patient_id']?.toString() == id)
          .toList();
    }
    final response = await http.get(
      Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/ordonnances'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    if (response.statusCode != 200) {
      throw Exception('Ordonnances indisponibles');
    }
    final records = (jsonDecode(response.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    return records;
  }

  Future<void> _editPatient() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PatientFormPage(
          token: widget.token,
          patient: widget.patient,
          role: widget.role,
        ),
      ),
    );
    if (updated == true && mounted) setState(() {});
  }

  void _newConsultation() {
    if (widget.role?.toLowerCase() != 'medecin' &&
        widget.role?.toLowerCase() != 'infirmier') {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultationFormPage(
          token: widget.token,
          initialPatientId: widget.patient['id']?.toString(),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _recordFuture = _loadRecord());
    });
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final name = '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    return Scaffold(
      backgroundColor: _AdminColors.background,
      body: FutureBuilder<_PatientRecordData>(
        future: _recordFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _PatientRecordData.empty();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 46,
                backgroundColor: _AdminColors.teal,
                child: Text(
                  _recordInitials(patient),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Dossier patient',
                style: TextStyle(color: _AdminColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(
                  color: _AdminColors.text,
                  fontSize: 29,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_patientAge(patient['date_naissance']) ?? 'Âge non renseigné'} ans · Patiente depuis janvier 2025',
                style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _editPatient,
                      style: FilledButton.styleFrom(
                        backgroundColor: _AdminColors.tealSoft,
                        foregroundColor: _AdminColors.teal,
                        minimumSize: const Size.fromHeight(74),
                      ),
                      child: const Text('Modifier'),
                    ),
                  ),
                  if (widget.role?.toLowerCase() == 'medecin' ||
                      widget.role?.toLowerCase() == 'infirmier') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _newConsultation,
                        icon: const Icon(Icons.add),
                        label: const Text('Nouvelle consultation'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(74),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 36),
              _PersonalInfoCard(
                patient: patient,
                showClinical: widget.hasClinicalAccess,
              ),
              const SizedBox(height: 26),
              _UpcomingAppointmentCard(
                appointments: data.appointments,
                context: context,
              ),
              if (widget.hasClinicalAccess) ...[
                const SizedBox(height: 26),
                _ConsultationHistoryCard(
                  consultations: data.consultations,
                  context: context,
                ),
              ],
              if (widget.role?.toLowerCase() == 'medecin') ...[
                const SizedBox(height: 26),
                _RecentPrescriptionsCard(
                  prescriptions: data.prescriptions,
                  context: context,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrescriptionsPage(
                        token: widget.token,
                        patientId: patient['id']?.toString(),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PatientRecordData {
  const _PatientRecordData({
    required this.consultations,
    required this.appointments,
    required this.prescriptions,
  });

  const _PatientRecordData.empty()
    : consultations = const [],
      appointments = const [],
      prescriptions = const [];

  final List<Map<String, dynamic>> consultations;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> prescriptions;
}

class _PersonalInfoCard extends StatelessWidget {
  const _PersonalInfoCard({required this.patient, required this.showClinical});

  final Map<String, dynamic> patient;
  final bool showClinical;

  @override
  Widget build(BuildContext context) => _RecordSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informations personnelles', style: _RecordTitle.style),
        const SizedBox(height: 30),
        _ProfileValue(
          label: 'Date de naissance',
          value: _formatRecordDate(patient['date_naissance']),
        ),
        _ProfileValue(
          label: 'Téléphone',
          value: patient['telephone']?.toString() ?? 'Non renseigné',
        ),
        _ProfileValue(
          label: 'Adresse',
          value: patient['adresse']?.toString() ?? 'Non renseignée',
        ),
        if (showClinical)
          _ProfileValue(
            label: 'Groupe sanguin',
            value: _bloodGroupLabel(patient['groupe_sanguin']),
          ),
        if (showClinical)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF8F8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFB9E5E5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.favorite_border, color: _AdminColors.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Allergies connues',
                        style: TextStyle(
                          color: _AdminColors.teal,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        patient['allergies']?.toString().trim().isNotEmpty ==
                                true
                            ? patient['allergies'].toString()
                            : 'Aucune allergie\nrenseignée',
                        style: const TextStyle(
                          color: _AdminColors.muted,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ProfileValue extends StatelessWidget {
  const _ProfileValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: _AdminColors.muted, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            color: _AdminColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
    ),
    child: child,
  );
}

class _RecordTitle {
  static const style = TextStyle(
    color: _AdminColors.text,
    fontSize: 20,
    fontWeight: FontWeight.w500,
  );
}

class _UpcomingAppointmentCard extends StatelessWidget {
  const _UpcomingAppointmentCard({
    required this.appointments,
    required this.context,
  });

  final List<Map<String, dynamic>> appointments;
  final BuildContext context;

  @override
  Widget build(BuildContext _) {
    final upcoming = appointments.where((item) {
      final status = item['statut']?.toString().toLowerCase() ?? '';
      return status != 'annule' && status != 'annulé' && status != 'termine';
    }).toList();
    final appointment = upcoming.isEmpty ? null : upcoming.first;
    final date = appointment == null
        ? null
        : DateTime.tryParse(appointment['date_heure']?.toString() ?? '');
    return _RecordSection(
      child: appointment == null
          ? const _EmptyRecordSection(
              title: 'Rendez-vous à venir',
              subtitle: 'Aucun rendez-vous programmé.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Rendez-vous à venir',
                        style: _RecordTitle.style,
                      ),
                    ),
                    _RecordStatus(
                      label: appointment['statut']?.toString() ?? 'Confirmé',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  appointment['motif']?.toString() ?? 'Consultation',
                  style: const TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Text(
                      date == null ? '--' : '${date.day}',
                      style: const TextStyle(
                        color: _AdminColors.teal,
                        fontSize: 46,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      date == null
                          ? 'Date non renseignée'
                          : _recordMonthYear(date),
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Container(height: 70, width: 1, color: _AdminColors.border),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        date == null
                            ? 'Heure non renseignée'
                            : '${TimeOfDay.fromDateTime(date).format(context)} · ${appointment['motif'] ?? 'Consultation'}',
                        style: const TextStyle(
                          color: _AdminColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ConsultationHistoryCard extends StatelessWidget {
  const _ConsultationHistoryCard({
    required this.consultations,
    required this.context,
  });

  final List<Map<String, dynamic>> consultations;
  final BuildContext context;

  @override
  Widget build(BuildContext _) => _RecordSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Historique des consultations',
                style: _RecordTitle.style,
              ),
            ),
            Text(
              'Voir tout',
              style: TextStyle(
                color: _AdminColors.teal,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.chevron_right, color: _AdminColors.teal),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Les dernières consultations',
          style: TextStyle(color: _AdminColors.muted, fontSize: 16),
        ),
        const SizedBox(height: 18),
        if (consultations.isEmpty)
          const Text(
            'Aucune consultation enregistrée.',
            style: TextStyle(color: _AdminColors.muted, fontSize: 15),
          )
        else
          for (
            var index = 0;
            index < consultations.length && index < 4;
            index++
          )
            _TimelineItem(
              record: consultations[index],
              isLast: index == consultations.length - 1 || index == 3,
              context: context,
            ),
      ],
    ),
  );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.record,
    required this.isLast,
    required this.context,
  });

  final Map<String, dynamic> record;
  final bool isLast;
  final BuildContext context;

  @override
  Widget build(BuildContext _) {
    final date = DateTime.tryParse(record['date']?.toString() ?? '');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const Icon(Icons.circle, size: 12, color: _AdminColors.teal),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1, color: _AdminColors.tealSoft),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record['motif']?.toString() ?? 'Consultation',
                    style: const TextStyle(
                      color: _AdminColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${date == null ? 'Date non renseignée' : MaterialLocalizations.of(context).formatFullDate(date)} · Dr. ${record['medecin_nom'] ?? ''}',
                    style: const TextStyle(
                      color: _AdminColors.muted,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPrescriptionsCard extends StatelessWidget {
  const _RecentPrescriptionsCard({
    required this.prescriptions,
    required this.context,
    required this.onTap,
  });

  final List<Map<String, dynamic>> prescriptions;
  final BuildContext context;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext _) => _RecordSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Ordonnances récentes', style: _RecordTitle.style),
            ),
            InkWell(
              onTap: onTap,
              child: const Row(
                children: [
                  Text(
                    'Voir tout',
                    style: TextStyle(
                      color: _AdminColors.teal,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: _AdminColors.teal),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Documents médicaux',
          style: TextStyle(color: _AdminColors.muted, fontSize: 16),
        ),
        const SizedBox(height: 14),
        if (prescriptions.isEmpty)
          const Text(
            'Aucune ordonnance récente.',
            style: TextStyle(color: _AdminColors.muted, fontSize: 15),
          )
        else
          for (final prescription in prescriptions.take(3))
            _PrescriptionSummary(prescription: prescription),
      ],
    ),
  );
}

class _PrescriptionSummary extends StatelessWidget {
  const _PrescriptionSummary({required this.prescription});

  final Map<String, dynamic> prescription;

  @override
  Widget build(BuildContext context) {
    final lines = (prescription['lignes'] as List<dynamic>?) ?? const [];
    final title = lines.isEmpty
        ? 'Ordonnance médicale'
        : (lines.first as Map<String, dynamic>)['medicament']?.toString() ??
              'Traitement';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _AdminColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _AdminColors.tealSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: _AdminColors.teal,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatRecordDate(prescription['date_emission']),
                  style: const TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.download_outlined, color: _AdminColors.muted),
        ],
      ),
    );
  }
}

class _EmptyRecordSection extends StatelessWidget {
  const _EmptyRecordSection({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: _RecordTitle.style),
      const SizedBox(height: 12),
      Text(subtitle, style: const TextStyle(color: _AdminColors.muted)),
    ],
  );
}

class _RecordStatus extends StatelessWidget {
  const _RecordStatus({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFFE2F3EF),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFA8DCCC)),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Color(0xFF249B86), fontSize: 13),
    ),
  );
}

String _formatRecordDate(Object? value) {
  if (value == null || value.toString().isEmpty) return 'Non renseignée';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return value.toString();
  return '${date.day} ${_recordMonth(date.month)} ${date.year}';
}

String _recordMonth(int month) => const [
  '',
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
][month.clamp(0, 12)];

String _recordMonthYear(DateTime date) =>
    '${_recordMonth(date.month).substring(0, 3).toUpperCase()}\n${date.year}';

String _bloodGroupLabel(Object? value) {
  final group = value?.toString().trim();
  if (group == null || group.isEmpty) return 'Non renseigné';
  return group == 'O+' ? 'O positif' : group;
}

String _recordInitials(Map<String, dynamic> patient) {
  final values = [patient['prenom'], patient['nom']]
      .where((value) => value != null && value.toString().trim().isNotEmpty)
      .map((value) => value.toString().trim()[0].toUpperCase())
      .take(2);
  return values.join();
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
        automaticallyImplyLeading: false,
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
              Text(
                _error!,
                style: const TextStyle(
                  color: _AdminColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
