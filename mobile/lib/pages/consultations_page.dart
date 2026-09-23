part of '../main.dart';

class ConsultationsFeaturePage extends StatelessWidget {
  const ConsultationsFeaturePage({
    super.key,
    required this.token,
    this.canCreate = true,
  });
  final String token;
  final bool canCreate;
  @override
  Widget build(BuildContext context) =>
      ConsultationsPage(token: token, canCreate: canCreate);
}

class ConsultationFormPage extends StatelessWidget {
  const ConsultationFormPage({
    super.key,
    required this.token,
    this.initialPatientId,
  });
  final String token;
  final String? initialPatientId;
  @override
  Widget build(BuildContext context) =>
      NewConsultationPage(token: token, initialPatientId: initialPatientId);
}

class ConsultationsPage extends StatefulWidget {
  const ConsultationsPage({
    super.key,
    required this.token,
    this.canCreate = true,
  });
  final String token;
  final bool canCreate;
  @override
  State<ConsultationsPage> createState() => _ConsultationsPageState();
}

class _ConsultationsPageState extends State<ConsultationsPage> {
  late Future<List<Map<String, dynamic>>> _future;
  String _locationFilter = 'Toutes';
  String _statusFilter = 'Toutes';

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
      if (response.statusCode != 200) throw Exception('Erreur de chargement');
      final consultations = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final patientsResponse = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final patients = patientsResponse.statusCode == 200
          ? (jsonDecode(patientsResponse.body) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .toList()
          : const <Map<String, dynamic>>[];
      for (final item in consultations) {
        final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) =>
              candidate?['id']?.toString() == item['patient_id']?.toString(),
          orElse: () => null,
        );
        item['patient_nom'] = patient == null
            ? null
            : '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
        await LocalDatabase.instance.saveConsultation(item);
      }
      return consultations;
    } catch (_) {
      final local = await LocalDatabase.instance.getConsultations();
      final synced = local
          .where((item) => item['sync_status'] == 'synced')
          .toList();
      if (synced.isNotEmpty) return synced;
      rethrow;
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultationFormPage(token: widget.token),
      ),
    );
    if (created == true && mounted) {
      setState(() => _future = LocalDatabase.instance.getConsultations());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _AdminColors.background,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <Map<String, dynamic>>[];
            final filtered = all.where((item) {
              final locationMatch =
                  _locationFilter == 'Toutes' ||
                  _consultationLocation(item) == _locationFilter;
              final completed = _isCompletedConsultation(item);
              final statusMatch =
                  _statusFilter == 'Toutes' ||
                  (_statusFilter == 'Terminées' && completed) ||
                  (_statusFilter == 'En cours' && !completed);
              return locationMatch && statusMatch;
            }).toList();
            final homeCount = all
                .where((item) => _consultationLocation(item) == 'Domicile')
                .length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: _AdminColors.teal,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.medical_information_outlined,
                        color: Colors.white,
                        size: 31,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Consultations',
                            style: TextStyle(
                              color: _AdminColors.text,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Suivi clinique au cabinet ou à domicile.',
                            style: TextStyle(
                              color: _AdminColors.muted,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _ConsultationSummary(
                        icon: Icons.assignment_outlined,
                        label: 'Total',
                        value: '${all.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ConsultationSummary(
                        icon: Icons.home_outlined,
                        label: 'À domicile',
                        value: '$homeCount',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (widget.canCreate)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nouvelle consultation'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: _AdminColors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                const Text(
                  'Lieu de prise en charge',
                  style: TextStyle(
                    color: _AdminColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final location in const [
                      'Toutes',
                      'Cabinet',
                      'Domicile',
                    ])
                      ChoiceChip(
                        label: Text(location),
                        selected: _locationFilter == location,
                        onSelected: (_) =>
                            setState(() => _locationFilter = location),
                        selectedColor: _AdminColors.teal,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _locationFilter == location
                              ? Colors.white
                              : _AdminColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: const BorderSide(color: _AdminColors.border),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'État du suivi',
                  style: TextStyle(
                    color: _AdminColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in const [
                      'Toutes',
                      'En cours',
                      'Terminées',
                    ])
                      ChoiceChip(
                        label: Text(status),
                        selected: _statusFilter == status,
                        onSelected: (_) =>
                            setState(() => _statusFilter = status),
                        selectedColor: _AdminColors.teal,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          color: _statusFilter == status
                              ? Colors.white
                              : _AdminColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: const BorderSide(color: _AdminColors.border),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasError)
                  const _ConsultationMessage(
                    icon: Icons.cloud_off_outlined,
                    text: 'Impossible de charger les consultations.',
                  )
                else if (filtered.isEmpty)
                  const _ConsultationMessage(
                    icon: Icons.medical_information_outlined,
                    text: 'Aucune consultation pour ce filtre.',
                  )
                else
                  ...filtered.map(
                    (item) => _ConsultationCard(
                      consultation: item,
                      formatDate: _formatDate,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  String _formatDate(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'Date non renseignée'
        : MaterialLocalizations.of(context).formatFullDate(date);
  }
}

class _ConsultationSummary extends StatelessWidget {
  const _ConsultationSummary({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _AdminColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1006273A),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _AdminColors.tealSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _AdminColors.teal, size: 23),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: _AdminColors.muted, fontSize: 12),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: _AdminColors.text,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ConsultationMessage extends StatelessWidget {
  const _ConsultationMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
    ),
    child: Column(
      children: [
        Icon(icon, color: _AdminColors.muted, size: 40),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _AdminColors.muted, fontSize: 15),
        ),
      ],
    ),
  );
}

class _ConsultationCard extends StatelessWidget {
  const _ConsultationCard({
    required this.consultation,
    required this.formatDate,
  });
  final Map<String, dynamic> consultation;
  final String Function(Object?) formatDate;
  @override
  Widget build(BuildContext context) {
    final location = _consultationLocation(consultation);
    final patient =
        consultation['patient_nom']?.toString() ??
        consultation['patient']?.toString() ??
        'Patient non renseigné';
    final diagnosis = consultation['diagnostic']?.toString();
    final motif = consultation['motif']?.toString() ?? 'Consultation';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
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
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  motif,
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _LocationPill(location: location),
            ],
          ),
          const SizedBox(height: 14),
          _ConsultationLine(icon: Icons.person_outline, text: patient),
          const SizedBox(height: 9),
          _ConsultationLine(
            icon: Icons.calendar_month_outlined,
            text: formatDate(consultation['date']),
          ),
          const SizedBox(height: 14),
          Text(
            diagnosis == null || diagnosis.isEmpty
                ? 'Aucun diagnostic renseigné'
                : diagnosis,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _AdminColors.muted,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: _AdminColors.teal,
                size: 18,
              ),
              SizedBox(width: 7),
              Text(
                'Consultation renseignée',
                style: TextStyle(
                  color: _AdminColors.teal,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationPill extends StatelessWidget {
  const _LocationPill({required this.location});
  final String location;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: location == 'Domicile'
          ? const Color(0xFFFFF4DF)
          : _AdminColors.tealSoft,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: location == 'Domicile'
            ? const Color(0xFFE8D5A6)
            : const Color(0xFFA8DCCC),
      ),
    ),
    child: Text(
      location,
      style: TextStyle(
        color: location == 'Domicile'
            ? const Color(0xFF9A6A14)
            : _AdminColors.teal,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ConsultationLine extends StatelessWidget {
  const _ConsultationLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _AdminColors.muted, size: 19),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _AdminColors.muted, fontSize: 14),
        ),
      ),
    ],
  );
}

String _consultationLocation(Map<String, dynamic> consultation) {
  final explicit = consultation['lieu']?.toString();
  if (explicit == 'Cabinet' || explicit == 'Domicile') return explicit!;
  return (consultation['notes']?.toString() ?? '').startsWith('Lieu: Domicile')
      ? 'Domicile'
      : 'Cabinet';
}

bool _isCompletedConsultation(Map<String, dynamic> consultation) {
  final status = (consultation['statut'] ?? consultation['status'] ?? '')
      .toString()
      .toLowerCase();
  if (status == 'termine' || status == 'terminé' || status == 'completed') {
    return true;
  }
  return (consultation['diagnostic']?.toString().trim().isNotEmpty ?? false) &&
      (consultation['notes']?.toString().trim().isNotEmpty ?? false);
}

class NewConsultationPage extends StatefulWidget {
  const NewConsultationPage({
    super.key,
    required this.token,
    this.initialPatientId,
  });
  final String token;
  final String? initialPatientId;
  @override
  State<NewConsultationPage> createState() => _NewConsultationPageState();
}

class _NewConsultationPageState extends State<NewConsultationPage> {
  final _formKey = GlobalKey<FormState>();
  final _motifController = TextEditingController();
  final _temperatureController = TextEditingController();
  final _tensionController = TextEditingController();
  final _diagnosticController = TextEditingController();
  final _notesController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _patientsFuture;
  String? _patientId;
  String _location = 'Cabinet';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _patientsFuture = _loadPatients();
    _patientId = widget.initialPatientId;
  }

  Future<List<Map<String, dynamic>>> _loadPatients() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Erreur de chargement des patients');
      }
      final patients = (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      for (final patient in patients) {
        await LocalDatabase.instance.savePatient(patient);
      }
      return patients;
    } catch (_) {
      final local = await LocalDatabase.instance.getPatients();
      return local
          .where((patient) => patient['sync_status'] == 'synced')
          .toList();
    }
  }

  @override
  void dispose() {
    _motifController.dispose();
    _temperatureController.dispose();
    _tensionController.dispose();
    _diagnosticController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _patientId == null) return;
    final payload = <String, dynamic>{
      'patient_id': _patientId,
      'motif': _motifController.text.trim(),
      'lieu': _location,
      'temperature': _temperatureController.text.trim().isEmpty
          ? null
          : _temperatureController.text.trim(),
      'tension_arterielle': _tensionController.text.trim().isEmpty
          ? null
          : _tensionController.text.trim(),
      'diagnostic': _diagnosticController.text.trim().isEmpty
          ? null
          : _diagnosticController.text.trim(),
      'notes': 'Lieu: $_location\n${_notesController.text.trim()}'.trim(),
    };
    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/consultations'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode != 201) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      final saved = jsonDecode(response.body) as Map<String, dynamic>;
      await LocalDatabase.instance.saveConsultation(saved);
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

  Widget _formLabel(String label) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        color: _AdminColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String? _validateTemperature(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final temperature = double.tryParse(text.replaceAll(',', '.'));
    return temperature == null || temperature < 25 || temperature > 45
        ? 'Valeur entre 25 et 45 °C'
        : null;
  }

  String? _validateBloodPressure(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^\d{2,3}\s*/\s*\d{2,3}$').hasMatch(text)
        ? null
        : 'Format attendu : 120/80';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _AdminColors.background,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _patientsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erreur : ${snapshot.error}'));
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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
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
                      style: TextStyle(color: _AdminColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Nouvelle consultation',
                      style: TextStyle(
                        color: _AdminColors.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Renseignez les informations nécessaires pour continuer.',
                      style: TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Divider(color: _AdminColors.border),
                    ),
                    _formLabel('Patient'),
                    DropdownButtonFormField<String>(
                      initialValue: _patientId,
                      decoration: const InputDecoration(
                        hintText: 'Rechercher un patient',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: patients
                          .map(
                            (patient) => DropdownMenuItem<String>(
                              value: patient['id'] as String,
                              child: Text(
                                '${patient['prenom']} ${patient['nom']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _patientId = value),
                      validator: (value) =>
                          value == null ? 'Sélectionnez un patient' : null,
                    ),
                    _formLabel('Lieu de consultation'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Cabinet',
                          label: Text('Cabinet'),
                          icon: Icon(Icons.local_hospital_outlined),
                        ),
                        ButtonSegment(
                          value: 'Domicile',
                          label: Text('Domicile'),
                          icon: Icon(Icons.home_outlined),
                        ),
                      ],
                      selected: {_location},
                      onSelectionChanged: (value) =>
                          setState(() => _location = value.first),
                    ),
                    _formLabel('Constantes vitales'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _temperatureController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Température',
                              hintText: '37,0 °C',
                              prefixIcon: Icon(Icons.thermostat_outlined),
                            ),
                            validator: _validateTemperature,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _tensionController,
                            keyboardType: TextInputType.text,
                            decoration: const InputDecoration(
                              labelText: 'Tension artérielle',
                              hintText: '120/80 mmHg',
                              prefixIcon: Icon(Icons.favorite_border),
                            ),
                            validator: _validateBloodPressure,
                          ),
                        ),
                      ],
                    ),
                    _formLabel('Motif / détails'),
                    TextFormField(
                      controller: _motifController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Décrivez le motif...',
                        prefixIcon: Icon(Icons.help_outline_rounded),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Le motif est obligatoire'
                          : null,
                    ),
                    _formLabel('Diagnostic'),
                    TextFormField(
                      controller: _diagnosticController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Diagnostic de la consultation',
                        prefixIcon: Icon(Icons.monitor_heart_outlined),
                      ),
                    ),
                    _formLabel('Notes et plan de suivi'),
                    TextFormField(
                      controller: _notesController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText:
                            'Recommandations, traitement, prochaine étape...',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(
                          _saving ? 'Enregistrement...' : 'Enregistrer',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: _AdminColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
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
        );
      },
    ),
  );
}
