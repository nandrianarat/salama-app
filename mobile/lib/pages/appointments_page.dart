part of '../main.dart';

/// Appointments feature entry point.
class AppointmentsPage extends StatelessWidget {
  const AppointmentsPage({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) => RendezVousPage(token: token);
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
                    'Tous les rendez-vous',
                    style: TextStyle(
                      color: Color(0xFF1D2A35),
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${appointments.length} rendez-vous au total',
                    style: const TextStyle(
                      color: Color(0xFF6D7C88),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
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
                          selectedColor: const Color(0xFF1DA9A7),
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
                                  ? const Color(0xFF1DA9A7)
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
