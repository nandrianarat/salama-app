part of '../main.dart';

/// Appointments feature entry point.
class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({
    super.key,
    required this.token,
    this.role,
    this.patientId,
  });

  final String token;
  final String? role;
  final String? patientId;

  @override
  Widget build(BuildContext context) =>
      RendezVousPage(token: token, role: role, patientId: patientId);
}

class RendezVousPage extends StatefulWidget {
  const RendezVousPage({
    super.key,
    required this.token,
    this.role,
    this.patientId,
  });

  final String token;
  final String? role;
  final String? patientId;

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
      final patientsResponse = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final personnelResponse = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/personnel'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final patients = patientsResponse.statusCode == 200
          ? (jsonDecode(patientsResponse.body) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .toList()
          : const <Map<String, dynamic>>[];
      final personnel = personnelResponse.statusCode == 200
          ? (jsonDecode(personnelResponse.body) as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .toList()
          : const <Map<String, dynamic>>[];
      for (final appointment in appointments) {
        final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
          (item) =>
              item?['id']?.toString() == appointment['patient_id']?.toString(),
          orElse: () => null,
        );
        final doctor = personnel.cast<Map<String, dynamic>?>().firstWhere(
          (item) =>
              item?['id']?.toString() == appointment['medecin_id']?.toString(),
          orElse: () => null,
        );
        appointment['patient_nom'] = patient == null
            ? null
            : '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
        appointment['medecin_nom'] = doctor?['nom'];
        await LocalDatabase.instance.saveRendezVous(appointment);
      }
      return appointments;
    } catch (_) {
      final local = await LocalDatabase.instance.getRendezVous();
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  String _selectedFilter = 'Tous';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F3),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _future = _load()),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              final appointments =
                  snapshot.data ?? const <Map<String, dynamic>>[];
              final filtered = _filterAppointments(appointments);

              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  const Text(
                    'Planning du centre',
                    style: TextStyle(
                      color: Color(0xFF547080),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Rendez-vous',
                    style: TextStyle(
                      color: Color(0xFF06263A),
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Organisez et suivez les rendez-vous de votre équipe.',
                    style: TextStyle(
                      color: Color(0xFF547080),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final created = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _NewAppointmentPage(
                              token: widget.token,
                              role: widget.role,
                              patientId: widget.patientId,
                            ),
                          ),
                        );
                        if (created == true && mounted) {
                          setState(() => _future = _load());
                        }
                      },
                      icon: const Icon(Icons.add, size: 22),
                      label: const Text('Nouveau rendez-vous'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: const Color(0xFF087F88),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _selectedFilter == 'En attente'
                        ? 'En attente'
                        : 'Tous les rendez-vous',
                    style: const TextStyle(
                      color: Color(0xFF1D2A35),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final filter in const [
                        'Tous',
                        'En attente',
                        'Confirmé',
                        'Terminé',
                        'Annulé',
                      ])
                        ChoiceChip(
                          label: Text(filter),
                          selected: _selectedFilter == filter,
                          onSelected: (_) =>
                              setState(() => _selectedFilter = filter),
                          selectedColor: const Color(0xFF087F88),
                          backgroundColor: const Color(0xFFF0F1EF),
                          labelStyle: TextStyle(
                            color: _selectedFilter == filter
                                ? Colors.white
                                : const Color(0xFF1D2A35),
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: _selectedFilter == filter
                                  ? const Color(0xFF087F88)
                                  : const Color(0xFFD7D9D6),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Center(child: CircularProgressIndicator())
                  else if (snapshot.hasError)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Erreur : ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF6D7C88)),
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Aucun rendez-vous pour ce filtre.',
                            style: TextStyle(color: Color(0xFF6D7C88)),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final appointment in filtered)
                      _AppointmentPanelCard(
                        appointment: appointment,
                        onConfirm: () => _updateStatus(appointment, 'confirme'),
                        onCancel: () => _updateStatus(appointment, 'annule'),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterAppointments(
    List<Map<String, dynamic>> appointments,
  ) {
    if (_selectedFilter == 'Tous') return appointments;

    final normalized = _selectedFilter.toLowerCase();
    return appointments.where((appointment) {
      final status = (appointment['statut'] ?? '').toString().toLowerCase();
      if (normalized == 'en attente') {
        return status == 'en attente' || status == 'confirme';
      }
      if (normalized == 'confirmé') {
        return status == 'confirme' || status == 'confirmé';
      }
      if (normalized == 'terminé') {
        return status == 'termine' || status == 'terminé';
      }
      if (normalized == 'annulé') {
        return status == 'annule' || status == 'annulé';
      }
      return true;
    }).toList();
  }

  Future<void> _updateStatus(
    Map<String, dynamic> appointment,
    String status,
  ) async {
    final id = appointment['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      final response = await http.put(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/rendezvous/$id'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'statut': status}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) setState(() => _future = _load());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mise à jour impossible.')),
        );
      }
    }
  }
}

class _NewAppointmentPage extends StatefulWidget {
  const _NewAppointmentPage({required this.token, this.role, this.patientId});

  final String token;
  final String? role;
  final String? patientId;

  bool get isPatient => role?.toLowerCase() == 'patient';

  @override
  State<_NewAppointmentPage> createState() => _NewAppointmentPageState();
}

class _NewAppointmentPageState extends State<_NewAppointmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _motifController = TextEditingController();
  final _specialtyController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _patientsFuture;
  late Future<List<Map<String, dynamic>>> _doctorsFuture;
  String? _patientId;
  String? _doctorId;
  DateTime? _dateTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _patientId = widget.patientId;
    _patientsFuture = _loadPatients();
    _doctorsFuture = _loadDoctors();
  }

  @override
  void dispose() {
    _motifController.dispose();
    _specialtyController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadPatients() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) throw Exception();
      final decoded = jsonDecode(response.body);
      final values = decoded is Map<String, dynamic>
          ? decoded['data'] ?? decoded['items'] ?? []
          : decoded;
      return values is List
          ? values.whereType<Map<String, dynamic>>().toList()
          : const [];
    } catch (_) {
      return LocalDatabase.instance.getPatients();
    }
  }

  Future<List<Map<String, dynamic>>> _loadDoctors() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${_LoginPageState._apiBaseUrl}/api/v1/personnel?role=medecin',
        ),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) throw Exception();
      final decoded = jsonDecode(response.body);
      final values = decoded is Map<String, dynamic>
          ? decoded['personnel'] ?? decoded['data'] ?? decoded['items'] ?? []
          : decoded;
      return values is List
          ? values
                .whereType<Map<String, dynamic>>()
                .where((doctor) => _isDoctorRole(doctor['role']))
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  bool _isDoctorRole(Object? role) {
    final normalized = role?.toString().trim().toLowerCase().replaceAll(
      'é',
      'e',
    );
    return normalized == 'medecin' || normalized == 'doctor';
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _dateTime ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dateTime == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_dateTime!),
    );
    if (time == null) return;
    setState(() {
      _dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _dateTime == null ||
        _doctorId == null ||
        _patientId == null) {
      if (_dateTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez une date et une heure.')),
        );
      } else if (_doctorId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez un médecin spécialiste.')),
        );
      } else if (_patientId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier patient introuvable.')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    final payload = {
      'id': const Uuid().v4(),
      'patient_id': _patientId,
      'medecin_id': _doctorId,
      'date_heure': _dateTime!.toIso8601String(),
      'statut': 'confirme',
      'motif': _motifController.text.trim(),
    };
    try {
      final response = await http.post(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/rendezvous'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception();
      }
      final saved = jsonDecode(response.body) as Map<String, dynamic>;
      await LocalDatabase.instance.saveRendezVous(saved);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’enregistrer le rendez-vous.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F8F8),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD6E1E2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rova · Gestion médicale',
                  style: TextStyle(color: Color(0xFF547080), fontSize: 14),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Nouveau rendez-vous',
                  style: TextStyle(
                    color: Color(0xFF06263A),
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Renseignez les informations nécessaires pour continuer.',
                  style: TextStyle(
                    color: Color(0xFF547080),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Divider(color: Color(0xFFD6E1E2)),
                ),
                if (!widget.isPatient) ...[
                  _label('Patient'),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _patientsFuture,
                    builder: (context, snapshot) {
                      final patients = snapshot.data ?? const [];
                      return DropdownButtonFormField<String>(
                        initialValue: _patientId,
                        decoration: const InputDecoration(
                          hintText: 'Rechercher un patient',
                        ),
                        validator: (value) =>
                            value == null ? 'Sélectionnez un patient' : null,
                        items: patients
                            .map(
                              (patient) => DropdownMenuItem(
                                value: patient['id']?.toString(),
                                child: Text(
                                  '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'
                                      .trim(),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _patientId = value),
                      );
                    },
                  ),
                ],
                _label('Médecin spécialiste'),
                TextField(
                  controller: _specialtyController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher une spécialité ou une compétence',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _doctorsFuture,
                  builder: (context, snapshot) {
                    final query = _specialtyController.text
                        .trim()
                        .toLowerCase();
                    final doctors = (snapshot.data ?? const []).where((doctor) {
                      if (query.isEmpty) return true;
                      final name = (doctor['nom'] ?? '').toString();
                      final specialty = (doctor['specialite'] ?? '').toString();
                      return '$name $specialty'.toLowerCase().contains(query);
                    }).toList();
                    return Column(
                      children: doctors.isEmpty
                          ? [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Aucun médecin pour cette compétence.',
                                  style: TextStyle(color: Color(0xFF547080)),
                                ),
                              ),
                            ]
                          : doctors
                                .map(
                                  (doctor) => _DoctorChoiceTile(
                                    doctor: doctor,
                                    selected:
                                        _doctorId == doctor['id']?.toString(),
                                    onTap: () => setState(
                                      () =>
                                          _doctorId = doctor['id']?.toString(),
                                    ),
                                  ),
                                )
                                .toList(),
                    );
                  },
                ),
                _label('Date et heure'),
                InkWell(
                  onTap: _pickDateTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      hintText: 'jj/mm/aaaa --:--',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    child: Text(
                      _dateTime == null
                          ? 'jj/mm/aaaa --:--'
                          : '${MaterialLocalizations.of(context).formatMediumDate(_dateTime!)} ${TimeOfDay.fromDateTime(_dateTime!).format(context)}',
                    ),
                  ),
                ),
                _label('Motif / détails'),
                TextFormField(
                  controller: _motifController,
                  maxLines: 4,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Renseignez le motif'
                      : null,
                  decoration: const InputDecoration(
                    hintText: 'Décrivez le motif...',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Divider(color: Color(0xFFD6E1E2)),
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
                      backgroundColor: const Color(0xFF087F88),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF087F88),
                      backgroundColor: const Color(0xFFD6F0F1),
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

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF06263A),
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DoctorChoiceTile extends StatelessWidget {
  const _DoctorChoiceTile({
    required this.doctor,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> doctor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = doctor['nom']?.toString().trim().isNotEmpty == true
        ? doctor['nom'].toString()
        : 'Médecin';
    final specialty = doctor['specialite']?.toString().trim().isNotEmpty == true
        ? doctor['specialite'].toString()
        : 'Médecine générale';
    final orderNumber = doctor['numero_ordre']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF8F8) : const Color(0xFFF8FCFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF087F88)
                  : const Color(0xFFD6E1E2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFD6F0F1),
                foregroundColor: const Color(0xFF087F88),
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF06263A),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      specialty,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF547080),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                          (index) => const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Color(0xFFE3A72F),
                          ),
                        ),
                        if (orderNumber != null && orderNumber.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'N° d’ordre $orderNumber',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF547080),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: const Color(0xFF087F88),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentPanelCard extends StatelessWidget {
  const _AppointmentPanelCard({
    required this.appointment,
    required this.onConfirm,
    required this.onCancel,
  });

  final Map<String, dynamic> appointment;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(appointment['date_heure']?.toString() ?? '');
    final status = (appointment['statut']?.toString() ?? 'confirme')
        .toLowerCase();
    final statusLabel = status == 'annule' || status == 'annulé'
        ? 'Annulé'
        : status == 'termine' || status == 'terminé'
        ? 'Terminé'
        : status == 'confirme' || status == 'confirmé'
        ? 'En attente'
        : 'En attente';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F3),
        border: Border.all(color: const Color(0xFFD8DCD8)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  appointment['motif']?.toString() ?? 'Dermatologie',
                  style: const TextStyle(
                    color: Color(0xFF1F2A35),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEDFC5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    color: Color(0xFF1F2A35),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 18,
                color: Color(0xFF1DA9A7),
              ),
              const SizedBox(width: 8),
              Text(
                date == null
                    ? 'Date non renseignée'
                    : MaterialLocalizations.of(context).formatFullDate(date),
                style: const TextStyle(
                  color: Color(0xFF1F2A35),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.access_time_rounded,
                size: 18,
                color: Color(0xFF1DA9A7),
              ),
              const SizedBox(width: 8),
              Text(
                date == null
                    ? '--:--'
                    : TimeOfDay.fromDateTime(date).format(context),
                style: const TextStyle(
                  color: Color(0xFF1F2A35),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.person_rounded,
                size: 18,
                color: Color(0xFF1DA9A7),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  appointment['patient_nom']?.toString() ??
                      'Patient non renseigné',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2A35),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Motif : Consultation pour eczéma',
            style: TextStyle(
              color: Color(0xFF1F2A35),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1DA9A7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Confirmer'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEA5C5C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFD7D9D6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Annuler'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormIntro extends StatelessWidget {
  const _FormIntro({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Color(0xFF132238),
        ),
      ),
      const SizedBox(height: 7),
      Text(description, style: const TextStyle(color: Color(0xFF708198))),
    ],
  );
}

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF708198), fontSize: 11),
        ),
      ],
    ),
  );
}
