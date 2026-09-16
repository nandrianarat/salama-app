part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.token,
    required this.role,
    required this.displayName,
  });

  final String token;
  final String role;
  final String displayName;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  Timer? _syncTimer;
  bool _syncing = false;
  late Future<_AdminSnapshot> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    _syncPendingData();
    _syncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _syncPendingData(),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<_AdminSnapshot> _loadDashboard() async {
    final headers = {'Authorization': 'Bearer ${widget.token}'};
    try {
      final responses = await Future.wait([
        http
            .get(
              Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/patients'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 5)),
        http
            .get(
              Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/rendezvous'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 5)),
      ]);
      if (responses.any((response) => response.statusCode != 200)) {
        throw Exception('Chargement impossible');
      }
      return _AdminSnapshot(
        patients: _decode(responses[0]),
        appointments: _decode(responses[1]),
      );
    } catch (_) {
      return _AdminSnapshot(
        patients: await LocalDatabase.instance.getPatients(),
        appointments: await LocalDatabase.instance.getRendezVous(),
      );
    }
  }

  List<Map<String, dynamic>> _decode(http.Response response) =>
      (jsonDecode(response.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();

  Future<void> _syncPendingData() async {
    if (_syncing || !await _isBackendReachable() || !mounted) return;
    final pending = await LocalDatabase.instance.getPendingOperationCount();
    if (pending == 0 || !mounted) return;
    setState(() => _syncing = true);
    try {
      await SyncService(
        baseUrl: _LoginPageState._apiBaseUrl,
        token: widget.token,
      ).syncAll();
      if (mounted) setState(() => _dashboardFuture = _loadDashboard());
    } catch (_) {
      // Les operations restent locales et seront retentees plus tard.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<bool> _isBackendReachable() async {
    try {
      final response = await http
          .get(Uri.parse('${_LoginPageState._apiBaseUrl}/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _select(int index) => setState(() => _selectedIndex = index);

  Future<void> _updateAppointment(String id, String status) async {
    try {
      final response = await http.put(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/rendezvous/$id'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'statut': status}),
      );
      if (response.statusCode != 200) throw Exception();
      await LocalDatabase.instance.saveRendezVous(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      if (mounted) setState(() => _dashboardFuture = _loadDashboard());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de modifier le rendez-vous.'),
          ),
        );
      }
    }
  }

  Widget _content() {
    switch (_selectedIndex) {
      case 1:
        return AppointmentsPage(token: widget.token);
      case 2:
        return _UsersPage(token: widget.token);
      case 3:
        return ConsultationsFeaturePage(token: widget.token);
      case 4:
        return _DoctorsPage(token: widget.token);
      case 5:
        return _ProfilePage(
          token: widget.token,
          displayName: widget.displayName,
          role: widget.role,
        );
      case 6:
        return PrescriptionsPage(token: widget.token, canCreate: false);
      default:
        return widget.role.toLowerCase() == 'patient'
            ? _PatientDashboard(
                future: _dashboardFuture,
                displayName: widget.displayName,
                onAppointments: () => _select(1),
                onRetry: () =>
                    setState(() => _dashboardFuture = _loadDashboard()),
              )
            : widget.role.toLowerCase() == 'medecin'
            ? _DoctorDashboard(
                future: _dashboardFuture,
                displayName: widget.displayName,
                onAppointments: () => _select(1),
                onComplete: (item) =>
                    _updateAppointment(item['id'].toString(), 'termine'),
                onCancel: (item) =>
                    _updateAppointment(item['id'].toString(), 'annule'),
                onRetry: () =>
                    setState(() => _dashboardFuture = _loadDashboard()),
              )
            : _AdminDashboard(
                future: _dashboardFuture,
                displayName: widget.displayName,
                onAppointments: () => _select(1),
                onUsers: () => _select(2),
                onComplete: (item) =>
                    _updateAppointment(item['id'].toString(), 'termine'),
                onCancel: (item) =>
                    _updateAppointment(item['id'].toString(), 'annule'),
                onRetry: () =>
                    setState(() => _dashboardFuture = _loadDashboard()),
              );
    }
  }

  Future<void> _logout() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _roleKey);
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    return Scaffold(
      backgroundColor: _AdminColors.background,
      drawer: wide
          ? null
          : widget.role.toLowerCase() == 'patient'
          ? _PatientDrawer(
              selectedIndex: _selectedIndex,
              displayName: widget.displayName,
              onSelect: _select,
              onLogout: _logout,
            )
          : widget.role.toLowerCase() == 'medecin'
          ? _DoctorDrawer(
              selectedIndex: _selectedIndex,
              displayName: widget.displayName,
              onSelect: _select,
              onLogout: _logout,
            )
          : _AdminDrawer(
              selectedIndex: _selectedIndex,
              displayName: widget.displayName,
              onSelect: _select,
              onLogout: _logout,
            ),
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: _AdminColors.background,
              elevation: 0,
              title: widget.role.toLowerCase() == 'patient'
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: _AdminColors.teal,
                          child: Icon(
                            Icons.monitor_heart_outlined,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Rova.',
                          style: TextStyle(
                            color: _AdminColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : widget.role.toLowerCase() == 'medecin'
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: _AdminColors.teal,
                          child: Icon(
                            Icons.monitor_heart_outlined,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Rova.',
                          style: TextStyle(
                            color: _AdminColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      switch (_selectedIndex) {
                        1 => 'Rendez-vous',
                        2 => 'Utilisateurs',
                        3 => 'Consultations',
                        6 => 'Mes ordonnances',
                        _ => 'Tableau de bord',
                      },
                      style: const TextStyle(
                        color: _AdminColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _AdminColors.tealSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.role.toLowerCase() == 'patient'
                            ? 'Patient'
                            : widget.role.toLowerCase() == 'medecin'
                            ? 'Médecin'
                            : widget.role == 'admin'
                            ? 'Administrateur'
                            : widget.role,
                        style: const TextStyle(
                          color: _AdminColors.teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide)
            _AdminSidebar(
              selectedIndex: _selectedIndex,
              displayName: widget.displayName,
              onSelect: _select,
              onLogout: _logout,
            ),
          Expanded(child: _content()),
        ],
      ),
    );
  }
}

class _AdminSnapshot {
  const _AdminSnapshot({required this.patients, required this.appointments});
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> appointments;
}

class _AdminColors {
  static const background = Color(0xFFF3F8F8);
  static const sidebar = Color(0xFFF8FCFC);
  static const border = Color(0xFFD6E1E2);
  static const teal = Color(0xFF087F88);
  static const tealSoft = Color(0xFFD6F0F1);
  static const danger = Color(0xFFD8485E);
  static const text = Color(0xFF06263A);
  static const muted = Color(0xFF547080);
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.selectedIndex,
    required this.displayName,
    required this.onSelect,
    required this.onLogout,
  });
  final int selectedIndex;
  final String displayName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, int)>[
      (Icons.grid_view_rounded, 'Tableau de bord', 0),
      (Icons.calendar_month_outlined, 'Rendez-vous', 1),
      (Icons.medical_information_outlined, 'Consultations', 3),
      (Icons.people_outline, 'Utilisateurs', 2),
      (Icons.medical_services_outlined, 'Médecins', 4),
      (Icons.account_circle_outlined, 'Mon profil', 5),
      (Icons.receipt_long_outlined, 'Mes ordonnances', 6),
    ];
    return Container(
      width: 315,
      decoration: const BoxDecoration(
        color: _AdminColors.sidebar,
        border: Border(right: BorderSide(color: _AdminColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: _AdminColors.teal,
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                SizedBox(width: 13),
                Text(
                  'Rova.',
                  style: TextStyle(
                    color: _AdminColors.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: Icon(
                  item.$1,
                  color: selectedIndex == item.$3
                      ? _AdminColors.teal
                      : _AdminColors.muted,
                ),
                title: Text(
                  item.$2,
                  style: TextStyle(
                    color: selectedIndex == item.$3
                        ? _AdminColors.text
                        : _AdminColors.muted,
                    fontWeight: selectedIndex == item.$3
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                selected: selectedIndex == item.$3,
                selectedTileColor: _AdminColors.tealSoft,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onTap: () => onSelect(item.$3),
              ),
            ),
          const Spacer(),
          const Divider(color: _AdminColors.border),
          ListTile(
            leading: const CircleAvatar(
              radius: 22,
              backgroundColor: _AdminColors.teal,
              child: Text(
                'AD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _AdminColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Administrateur',
              style: TextStyle(color: _AdminColors.muted),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: _AdminColors.muted),
            title: const Text(
              'Se déconnecter',
              style: TextStyle(color: _AdminColors.muted),
            ),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer({
    required this.selectedIndex,
    required this.displayName,
    required this.onSelect,
    required this.onLogout,
  });

  final int selectedIndex;
  final String displayName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _AdminColors.sidebar,
      child: _AdminSidebar(
        selectedIndex: selectedIndex,
        displayName: displayName,
        onSelect: (index) {
          Navigator.pop(context);
          onSelect(index);
        },
        onLogout: () {
          Navigator.pop(context);
          onLogout();
        },
      ),
    );
  }
}

class _DoctorDrawer extends StatelessWidget {
  const _DoctorDrawer({
    required this.selectedIndex,
    required this.displayName,
    required this.onSelect,
    required this.onLogout,
  });

  final int selectedIndex;
  final String displayName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: _AdminColors.sidebar,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 16, 18, 24),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 23,
                  backgroundColor: _AdminColors.teal,
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Text(
                    'Rova.',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: _AdminColors.muted),
                ),
              ],
            ),
          ),
          _DoctorNavItem(
            icon: Icons.grid_view_rounded,
            label: 'Tableau de bord',
            selected: selectedIndex == 0,
            onTap: () => _select(context, 0),
          ),
          _DoctorNavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Mon agenda',
            selected: selectedIndex == 1,
            onTap: () => _select(context, 1),
          ),
          _DoctorNavItem(
            icon: Icons.medical_information_outlined,
            label: 'Consultations',
            selected: selectedIndex == 3,
            onTap: () => _select(context, 3),
          ),
          _DoctorNavItem(
            icon: Icons.account_circle_outlined,
            label: 'Mon profil',
            selected: selectedIndex == 5,
            onTap: () => _select(context, 5),
          ),
          const Spacer(),
          const Divider(color: _AdminColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 20, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _AdminColors.teal,
                  child: Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AdminColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(25, 0, 20, 12),
            leading: const Icon(Icons.logout, color: _AdminColors.muted),
            title: const Text(
              'Se déconnecter',
              style: TextStyle(color: _AdminColors.muted),
            ),
            onTap: onLogout,
          ),
        ],
      ),
    ),
  );

  void _select(BuildContext context, int index) {
    Navigator.pop(context);
    onSelect(index);
  }
}

class _DoctorNavItem extends StatelessWidget {
  const _DoctorNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    child: ListTile(
      leading: Icon(
        icon,
        color: selected ? _AdminColors.teal : _AdminColors.muted,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? _AdminColors.text : _AdminColors.muted,
          fontSize: 17,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      selectedTileColor: _AdminColors.tealSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    ),
  );
}

class _DoctorDashboard extends StatelessWidget {
  const _DoctorDashboard({
    required this.future,
    required this.displayName,
    required this.onAppointments,
    required this.onComplete,
    required this.onCancel,
    required this.onRetry,
  });

  final Future<_AdminSnapshot> future;
  final String displayName;
  final VoidCallback onAppointments;
  final ValueChanged<Map<String, dynamic>> onComplete;
  final ValueChanged<Map<String, dynamic>> onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<_AdminSnapshot>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data == null) {
        return Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        );
      }
      final data = snapshot.data!;
      final appointments = [...data.appointments]
        ..sort((a, b) => _appointmentDate(a).compareTo(_appointmentDate(b)));
      final active = appointments.where((item) => !_isFinished(item)).toList();
      final pending = active
          .where(
            (item) =>
                (item['statut'] ?? '').toString().toLowerCase() == 'confirme',
          )
          .length;
      return RefreshIndicator(
        onRefresh: () async => onRetry(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          children: [
            const Text(
              'Médecin · Rova',
              style: TextStyle(color: _AdminColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 10),
            Text(
              'Bonjour ${_doctorFirstName(displayName)},\nbienvenue.',
              style: const TextStyle(
                color: _AdminColors.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 38),
            _DoctorMetricCard(
              icon: Icons.calendar_month_outlined,
              label: 'Consultations à venir',
              value: '${active.length}',
            ),
            _DoctorMetricCard(
              icon: Icons.event_available_outlined,
              label: 'À confirmer',
              value: '$pending',
            ),
            _DoctorMetricCard(
              icon: Icons.medical_services_outlined,
              label: 'Spécialité',
              value: 'Cardiologie',
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Flexible(
                  child: Text(
                    'Votre agenda à venir',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onAppointments,
                  child: const Text('Tout voir'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (active.isEmpty)
              const _EmptyAdminAppointments()
            else
              ...active
                  .take(5)
                  .map(
                    (item) => _DoctorAppointmentCard(
                      item: item,
                      patients: data.patients,
                      onComplete: () => onComplete(item),
                      onCancel: () => onCancel(item),
                    ),
                  ),
          ],
        ),
      );
    },
  );
}

class _DoctorMetricCard extends StatelessWidget {
  const _DoctorMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1406273A),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _AdminColors.tealSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: _AdminColors.teal, size: 30),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: _AdminColors.muted, fontSize: 17),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _AdminColors.text,
                  fontSize: 30,
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

class _DoctorAppointmentCard extends StatelessWidget {
  const _DoctorAppointmentCard({
    required this.item,
    required this.patients,
    required this.onComplete,
    required this.onCancel,
  });

  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> patients;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
      (value) => value?['id']?.toString() == item['patient_id']?.toString(),
      orElse: () => null,
    );
    final name = patient == null
        ? (item['patient_nom']?.toString() ?? 'Patient')
        : '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    final date = DateTime.tryParse(_appointmentDate(item));
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1406273A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['motif']?.toString() ?? 'Consultation',
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusPill(label: 'Confirmé'),
            ],
          ),
          const SizedBox(height: 16),
          _AppointmentLine(
            icon: Icons.calendar_month_outlined,
            text: date == null
                ? 'Date indisponible'
                : MaterialLocalizations.of(context).formatFullDate(date),
          ),
          const SizedBox(height: 10),
          _AppointmentLine(
            icon: Icons.access_time_outlined,
            text: date == null
                ? '--:--'
                : TimeOfDay.fromDateTime(date).format(context),
          ),
          const SizedBox(height: 10),
          _AppointmentLine(icon: Icons.person_outline, text: name),
          const SizedBox(height: 12),
          Text(
            'Motif : ${item['motif']?.toString() ?? 'Consultation'}',
            style: const TextStyle(color: _AdminColors.text, fontSize: 16),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: onComplete,
                style: FilledButton.styleFrom(
                  backgroundColor: _AdminColors.tealSoft,
                  foregroundColor: _AdminColors.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                child: const Text('Marquer terminé'),
              ),
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _AdminColors.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE2F3EF),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFA8DCCC)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xFF249B86),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _AppointmentLine extends StatelessWidget {
  const _AppointmentLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _AdminColors.muted, size: 20),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
        ),
      ),
    ],
  );
}

bool _isFinished(Map<String, dynamic> item) {
  final status = (item['statut'] ?? '').toString().toLowerCase();
  return status == 'termine' ||
      status == 'terminé' ||
      status == 'annule' ||
      status == 'annulé';
}

String _doctorFirstName(String name) {
  final value = name.trim();
  if (value.isEmpty) return 'Dr.';
  final parts = value.split(RegExp(r'\s+'));
  return parts.length > 1 && parts.first.toLowerCase() == 'dr.'
      ? 'Dr. ${parts[1]}'
      : value;
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2);
  return parts.map((part) => part[0].toUpperCase()).join();
}

class _PatientDrawer extends StatelessWidget {
  const _PatientDrawer({
    required this.selectedIndex,
    required this.displayName,
    required this.onSelect,
    required this.onLogout,
  });
  final int selectedIndex;
  final String displayName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: _AdminColors.sidebar,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 16, 18, 24),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 23,
                  backgroundColor: _AdminColors.teal,
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Text(
                    'Rova.',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: _AdminColors.muted),
                ),
              ],
            ),
          ),
          _DoctorNavItem(
            icon: Icons.grid_view_rounded,
            label: 'Tableau de bord',
            selected: selectedIndex == 0,
            onTap: () => _select(context, 0),
          ),
          _DoctorNavItem(
            icon: Icons.event_available_outlined,
            label: 'Prendre rendez-vous',
            selected: false,
            onTap: () => _select(context, 1),
          ),
          _DoctorNavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Mes rendez-vous',
            selected: selectedIndex == 1,
            onTap: () => _select(context, 1),
          ),
          _DoctorNavItem(
            icon: Icons.receipt_long_outlined,
            label: 'Mes ordonnances',
            selected: selectedIndex == 6,
            onTap: () => _select(context, 6),
          ),
          _DoctorNavItem(
            icon: Icons.account_circle_outlined,
            label: 'Mon profil',
            selected: selectedIndex == 5,
            onTap: () => _select(context, 5),
          ),
          const Spacer(),
          const Divider(color: _AdminColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 20, 20, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _AdminColors.teal,
                  child: Text(
                    _initials(displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AdminColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(25, 0, 20, 12),
            leading: const Icon(Icons.logout, color: _AdminColors.muted),
            title: const Text(
              'Se déconnecter',
              style: TextStyle(color: _AdminColors.muted),
            ),
            onTap: onLogout,
          ),
        ],
      ),
    ),
  );

  void _select(BuildContext context, int index) {
    Navigator.pop(context);
    onSelect(index);
  }
}

class _PatientDashboard extends StatelessWidget {
  const _PatientDashboard({
    required this.future,
    required this.displayName,
    required this.onAppointments,
    required this.onRetry,
  });

  final Future<_AdminSnapshot> future;
  final String displayName;
  final VoidCallback onAppointments;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<_AdminSnapshot>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data == null) {
        return Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        );
      }
      final data = snapshot.data!;
      final appointments = [...data.appointments]
        ..sort((a, b) => _appointmentDate(a).compareTo(_appointmentDate(b)));
      final upcoming = appointments
          .where((item) => !_isFinished(item))
          .toList();
      final pending = upcoming
          .where(
            (item) => (item['statut'] ?? '').toString().toLowerCase().contains(
              'attente',
            ),
          )
          .length;
      final confirmed = upcoming.length - pending;
      final firstName = displayName.trim().split(RegExp(r'\s+')).first;
      return RefreshIndicator(
        onRefresh: () async => onRetry(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 36),
          children: [
            const Text(
              'Patient · Rova',
              style: TextStyle(color: _AdminColors.muted, fontSize: 17),
            ),
            const SizedBox(height: 10),
            Text(
              'Bonjour $firstName,\nbienvenue.',
              style: const TextStyle(
                color: _AdminColors.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 38),
            _PatientMetricCard(
              icon: Icons.calendar_month_outlined,
              label: 'Rendez-vous à venir',
              value: '${upcoming.length}',
            ),
            _PatientMetricCard(
              icon: Icons.event_outlined,
              label: 'En attente de\nconfirmation',
              value: '$pending',
            ),
            _PatientMetricCard(
              icon: Icons.event_available_outlined,
              label: 'Confirmés',
              value: '$confirmed',
            ),
            const SizedBox(height: 6),
            _PatientBookingCard(onTap: onAppointments),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Flexible(
                  child: Text(
                    'Vos prochains\nrendez-vous',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onAppointments,
                  child: const Text('Tout voir'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (upcoming.isEmpty)
              const _EmptyAdminAppointments()
            else
              ...upcoming
                  .take(5)
                  .map(
                    (item) => _PatientAppointmentCard(
                      item: item,
                      onCancel: onAppointments,
                    ),
                  ),
          ],
        ),
      );
    },
  );
}

class _PatientMetricCard extends StatelessWidget {
  const _PatientMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1406273A),
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _AdminColors.tealSoft,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: _AdminColors.teal, size: 30),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _AdminColors.muted,
                  fontSize: 17,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: _AdminColors.text,
                  fontSize: 30,
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

class _PatientBookingCard extends StatelessWidget {
  const _PatientBookingCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(30, 26, 24, 26),
    decoration: BoxDecoration(
      color: const Color(0xFFE8F3F3),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.event_available_outlined,
          color: _AdminColors.teal,
          size: 38,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Besoin d'une consultation?",
                style: TextStyle(
                  color: _AdminColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choisissez un médecin et réservez un créneau en quelques clics.',
                style: TextStyle(
                  color: _AdminColors.muted,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: _AdminColors.teal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                  ),
                  child: const Text('Prendre rendez-vous'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PatientAppointmentCard extends StatelessWidget {
  const _PatientAppointmentCard({required this.item, required this.onCancel});
  final Map<String, dynamic> item;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(_appointmentDate(item));
    final doctor = item['medecin_nom']?.toString() ?? 'Médecin non renseigné';
    final status = (item['statut'] ?? '').toString().toLowerCase();
    final label = status.contains('attente') ? 'En attente' : 'Confirmé';
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1406273A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item['motif']?.toString() ?? 'Consultation',
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusPill(label: label),
            ],
          ),
          const SizedBox(height: 16),
          _AppointmentLine(
            icon: Icons.calendar_month_outlined,
            text: date == null
                ? 'Date indisponible'
                : MaterialLocalizations.of(context).formatFullDate(date),
          ),
          const SizedBox(height: 10),
          _AppointmentLine(
            icon: Icons.access_time_outlined,
            text: date == null
                ? '--:--'
                : TimeOfDay.fromDateTime(date).format(context),
          ),
          const SizedBox(height: 10),
          _AppointmentLine(icon: Icons.medical_services_outlined, text: doctor),
          const SizedBox(height: 12),
          Text(
            'Motif : ${item['motif']?.toString() ?? 'Consultation'}',
            style: const TextStyle(color: _AdminColors.text, fontSize: 16),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: _AdminColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            ),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({
    required this.future,
    required this.displayName,
    required this.onAppointments,
    required this.onUsers,
    required this.onComplete,
    required this.onCancel,
    required this.onRetry,
  });
  final Future<_AdminSnapshot> future;
  final String displayName;
  final VoidCallback onAppointments;
  final VoidCallback onUsers;
  final ValueChanged<Map<String, dynamic>> onComplete;
  final ValueChanged<Map<String, dynamic>> onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminSnapshot>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          );
        }
        final data = snapshot.data!;
        final appointments = [...data.appointments]
          ..sort((a, b) => _appointmentDate(a).compareTo(_appointmentDate(b)));
        final pending = appointments
            .where(
              (item) =>
                  (item['statut']?.toString() ?? '').toLowerCase() ==
                  'confirme',
            )
            .length;
        return RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 18 : 40,
              24,
              MediaQuery.sizeOf(context).width < 600 ? 18 : 40,
              40,
            ),
            children: [
              const Text(
                'Administrateur · Rova',
                style: TextStyle(color: _AdminColors.muted, fontSize: 17),
              ),
              const SizedBox(height: 12),
              Text(
                'Bonjour ${displayName.isEmpty ? 'Rova' : displayName},\nbienvenue.',
                style: TextStyle(
                  color: _AdminColors.text,
                  fontSize: MediaQuery.sizeOf(context).width < 600 ? 26 : 31,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 34),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 700 ? 1 : 3;
                  final aspectRatio = constraints.maxWidth < 700 ? 4.1 : 2.5;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 16,
                    childAspectRatio: aspectRatio,
                    children: [
                      _AdminStat(
                        icon: Icons.calendar_month_outlined,
                        label: 'Rendez-vous au total',
                        value: '${appointments.length}',
                        onTap: onAppointments,
                      ),
                      _AdminStat(
                        icon: Icons.event_available_outlined,
                        label: 'En attente',
                        value: '$pending',
                        onTap: onAppointments,
                      ),
                      _AdminStat(
                        icon: Icons.people_outline,
                        label: 'Utilisateurs',
                        value: '${data.patients.length}',
                        onTap: onUsers,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Rendez-vous à venir',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: onAppointments,
                    child: const Text('Tout voir'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (appointments.isEmpty)
                const _EmptyAdminAppointments()
              else
                ...appointments
                    .take(5)
                    .map(
                      (item) => _AdminAppointmentCard(
                        item: item,
                        patients: data.patients,
                        onTap: onAppointments,
                        onComplete: () => onComplete(item),
                        onCancel: () => onCancel(item),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminStat extends StatelessWidget {
  const _AdminStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 112),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1406273A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _AdminColors.tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _AdminColors.teal, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: _AdminColors.text,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AdminAppointmentCard extends StatelessWidget {
  const _AdminAppointmentCard({
    required this.item,
    required this.patients,
    required this.onTap,
    required this.onComplete,
    required this.onCancel,
  });
  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> patients;
  final VoidCallback onTap;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
      (value) => value?['id']?.toString() == item['patient_id']?.toString(),
      orElse: () => null,
    );
    final name = patient == null
        ? (item['patient_nom']?.toString() ?? 'Patient')
        : '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    final date = DateTime.tryParse(_appointmentDate(item));
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item['motif']?.toString() ?? 'Rendez-vous',
          style: const TextStyle(
            color: _AdminColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${date == null ? 'Date indisponible' : MaterialLocalizations.of(context).formatFullDate(date)}  ·  ${date == null ? '--:--' : TimeOfDay.fromDateTime(date).format(context)}  ·  $name',
          style: const TextStyle(color: _AdminColors.muted, fontSize: 12),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: onComplete,
          style: FilledButton.styleFrom(
            backgroundColor: _AdminColors.tealSoft,
            foregroundColor: _AdminColors.teal,
          ),
          child: const Text('Marquer terminé'),
        ),
        OutlinedButton(
          onPressed: onCancel,
          style: OutlinedButton.styleFrom(foregroundColor: _AdminColors.danger),
          child: const Text('Annuler'),
        ),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _AdminColors.tealSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.calendar_month_outlined,
                      color: _AdminColors.teal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: details),
                ],
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAdminAppointments extends StatelessWidget {
  const _EmptyAdminAppointments();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Aucun rendez-vous enregistré.',
        style: TextStyle(color: _AdminColors.muted),
      ),
    ),
  );
}

class _RovaLogo extends StatelessWidget {
  const _RovaLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      Icons.medical_services_outlined,
      color: Colors.white,
      size: size * .52,
    ),
  );
}

class _ThemeToggleButton extends StatelessWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: _themeMode,
    builder: (context, mode, _) {
      final dark = mode == ThemeMode.dark;
      return IconButton(
        tooltip: dark ? 'Activer le mode clair' : 'Activer le mode sombre',
        onPressed: () =>
            _themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
        icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      );
    },
  );
}

class _UsersPage extends StatefulWidget {
  const _UsersPage({required this.token});

  final String token;

  @override
  State<_UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<_UsersPage> {
  final _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _usersFuture;
  String _roleFilter = 'Tous';

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/users'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) {
        throw Exception('Utilisateurs indisponibles');
      }
      final decoded = jsonDecode(response.body);
      final values = decoded is Map<String, dynamic>
          ? decoded['users'] ?? decoded['data'] ?? []
          : decoded;
      return (values as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _filteredUsers(List<Map<String, dynamic>> users) {
    final query = _searchController.text.trim().toLowerCase();
    return users.where((user) {
      final name = (user['nom'] ?? user['name'] ?? '').toString();
      final email = (user['email'] ?? '').toString();
      final role = (user['role'] ?? '').toString();
      final matchesSearch =
          query.isEmpty || '$name $email'.toLowerCase().contains(query);
      final matchesRole = _roleFilter == 'Tous' || role == _roleFilter;
      return matchesSearch && matchesRole;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        final users = _filteredUsers(snapshot.data ?? const []);
        return RefreshIndicator(
          onRefresh: () async => setState(() => _usersFuture = _loadUsers()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _AdminColors.teal,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.people_alt_outlined,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Utilisateurs',
                        style: TextStyle(
                          color: _AdminColors.text,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${snapshot.data?.length ?? 0} utilisateur(s)',
                        style: const TextStyle(
                          color: _AdminColors.muted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = SizedBox(
                    width: constraints.maxWidth > 760 ? 282 : double.infinity,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Rechercher par nom ou email',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: _AdminColors.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: _AdminColors.border,
                          ),
                        ),
                      ),
                    ),
                  );
                  final filters = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final role in const [
                        'Tous',
                        'Administrateur',
                        'Médecin',
                        'Secrétaire',
                        'Patient',
                      ])
                        ChoiceChip(
                          label: Text(role),
                          selected: _roleFilter == role,
                          onSelected: (_) => setState(() => _roleFilter = role),
                          selectedColor: _AdminColors.teal,
                          backgroundColor: Colors.transparent,
                          labelStyle: TextStyle(
                            color: _roleFilter == role
                                ? Colors.white
                                : _AdminColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: const BorderSide(color: _AdminColors.border),
                          ),
                        ),
                    ],
                  );
                  return constraints.maxWidth > 760
                      ? Row(
                          children: [
                            search,
                            const SizedBox(width: 14),
                            Expanded(child: filters),
                          ],
                        )
                      : Column(
                          children: [
                            search,
                            const SizedBox(height: 12),
                            filters,
                          ],
                        );
                },
              ),
              const SizedBox(height: 28),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else
                _UsersList(users: users),
            ],
          ),
        );
      },
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList({required this.users});

  final List<Map<String, dynamic>> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aucun utilisateur trouvé.',
            style: TextStyle(color: _AdminColors.muted),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < users.length; index++) ...[
            _UserListTile(user: users[index]),
            if (index < users.length - 1)
              const Divider(height: 1, color: _AdminColors.border),
          ],
        ],
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  const _UserListTile({required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final name = (user['nom'] ?? user['name'] ?? 'Utilisateur').toString();
    final email = (user['email'] ?? '').toString();
    final role = (user['role'] ?? 'Patient').toString();
    final specialty = (user['specialite'] ?? '').toString();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final isAdmin = role == 'Administrateur';
    final badgeColor = role == 'Médecin'
        ? const Color(0xFFE2F3EF)
        : role == 'Secrétaire'
        ? const Color(0xFFFFF4DF)
        : role == 'Patient'
        ? const Color(0xFFE7F0F1)
        : _AdminColors.teal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFFE4F1F2),
            child: Text(
              initials,
              style: const TextStyle(
                color: _AdminColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: _AdminColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  specialty.isEmpty ? email : '$email · $specialty',
                  style: const TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isAdmin ? _AdminColors.teal : badgeColor,
              borderRadius: BorderRadius.circular(999),
              border: isAdmin ? null : Border.all(color: _AdminColors.border),
            ),
            child: Text(
              role,
              style: TextStyle(
                color: isAdmin ? Colors.white : _AdminColors.teal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (!isAdmin) ...[
            const SizedBox(width: 18),
            const Icon(
              Icons.delete_outline,
              color: _AdminColors.muted,
              size: 21,
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorsPage extends StatefulWidget {
  const _DoctorsPage({required this.token});

  final String token;

  @override
  State<_DoctorsPage> createState() => _DoctorsPageState();
}

class _DoctorsPageState extends State<_DoctorsPage> {
  late Future<List<Map<String, dynamic>>> _doctorsFuture;

  @override
  void initState() {
    super.initState();
    _doctorsFuture = _loadDoctors();
  }

  Future<List<Map<String, dynamic>>> _loadDoctors() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/personnel'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200) throw Exception('Médecins indisponibles');
      final decoded = jsonDecode(response.body);
      final values = decoded is Map<String, dynamic>
          ? decoded['personnel'] ?? decoded['data'] ?? []
          : decoded;
      return (values as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .where(
            (doctor) =>
                (doctor['role'] ?? '').toString().toLowerCase() == 'medecin',
          )
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _doctorsFuture,
      builder: (context, snapshot) {
        final doctors = snapshot.data ?? const <Map<String, dynamic>>[];
        return RefreshIndicator(
          onRefresh: () async =>
              setState(() => _doctorsFuture = _loadDoctors()),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: _AdminColors.teal,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.medical_services_outlined,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Médecins',
                          style: TextStyle(
                            color: _AdminColors.text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${doctors.length} praticien(s) au centre\nRova',
                          style: const TextStyle(
                            color: _AdminColors.muted,
                            fontSize: 17,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (doctors.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucun médecin enregistré.',
                      style: TextStyle(color: _AdminColors.muted),
                    ),
                  ),
                )
              else
                ...doctors.map((doctor) => _DoctorCard(doctor: doctor)),
            ],
          ),
        );
      },
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.doctor});

  final Map<String, dynamic> doctor;

  @override
  Widget build(BuildContext context) {
    final name = (doctor['nom'] ?? doctor['name'] ?? 'Médecin').toString();
    final specialty = (doctor['specialite'] ?? 'Médecine générale').toString();
    final email = (doctor['email'] ?? doctor['login'] ?? 'Email non renseigné')
        .toString();
    final phone = (doctor['telephone'] ?? 'Téléphone non renseigné').toString();
    final activeAppointments = doctor['rendez_vous_actifs'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AdminColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1406273A),
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFD9F3F4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: _AdminColors.teal,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: _AdminColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F3EF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFA8DCCC)),
                      ),
                      child: Text(
                        specialty,
                        style: const TextStyle(
                          color: Color(0xFF249B86),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _DoctorContact(icon: Icons.mail_outline, value: email),
          const SizedBox(height: 12),
          _DoctorContact(icon: Icons.phone_outlined, value: phone),
          const Padding(
            padding: EdgeInsets.only(top: 20, bottom: 16),
            child: Divider(height: 1, color: _AdminColors.border),
          ),
          Text(
            '$activeAppointments rendez-vous actif${activeAppointments == 1 ? '' : 's'}',
            style: const TextStyle(
              color: _AdminColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorContact extends StatelessWidget {
  const _DoctorContact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: _AdminColors.muted, size: 20),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
        ),
      ),
    ],
  );
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({
    required this.token,
    required this.displayName,
    required this.role,
  });

  final String token;
  final String displayName;
  final String role;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _savingProfile = false;
  bool _savingPassword = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.displayName.isEmpty ? 'Utilisateur' : widget.displayName,
    );
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await http.get(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/auth/me'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      if (response.statusCode != 200 || !mounted) return;
      final profile = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() {
        _nameController.text =
            profile['nom']?.toString() ?? _nameController.text;
        _emailController.text =
            profile['email']?.toString() ?? profile['login']?.toString() ?? '';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);
    try {
      final response = await http.put(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/auth/me'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'nom': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'telephone': _phoneController.text.trim(),
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception();
      }
      _showMessage('Informations enregistrées.');
    } catch (_) {
      _showMessage('Impossible d’enregistrer les modifications.');
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _updatePassword() async {
    if (_newPasswordController.text.length < 6) {
      _showMessage('Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showMessage('Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      final response = await http.put(
        Uri.parse('${_LoginPageState._apiBaseUrl}/api/v1/auth/password'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'mot_de_passe': _newPasswordController.text}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception();
      }
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _showMessage('Mot de passe mis à jour.');
    } catch (_) {
      _showMessage('Impossible de mettre à jour le mot de passe.');
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.role.toLowerCase() == 'admin'
        ? 'Administrateur'
        : widget.role;
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 35,
              backgroundColor: _AdminColors.teal,
              child: Icon(
                Icons.account_circle_outlined,
                color: Colors.white,
                size: 43,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _nameController.text,
                    style: const TextStyle(
                      color: _AdminColors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$roleLabel ·',
                    style: const TextStyle(
                      color: _AdminColors.muted,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    _emailController.text,
                    style: const TextStyle(
                      color: _AdminColors.muted,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 34),
        _ProfileSection(
          title: 'Informations personnelles',
          description:
              'Mettez à jour vos coordonnées.\nL’email et le rôle ne sont pas modifiables.',
          children: [
            _ProfileField(label: 'Nom complet', controller: _nameController),
            _ProfileField(
              label: 'Email',
              controller: _emailController,
              enabled: false,
              keyboardType: TextInputType.emailAddress,
            ),
            _ProfileField(
              label: 'Téléphone',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _savingProfile ? null : _saveProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: _AdminColors.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
                child: Text(
                  _savingProfile
                      ? 'Enregistrement...'
                      : 'Enregistrer les modifications',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _ProfileSection(
          title: 'Sécurité',
          description: 'Changez votre mot de passe.',
          children: [
            _ProfileField(
              label: 'Nouveau mot de passe',
              controller: _newPasswordController,
              hintText: 'Au moins 6 caractères',
              obscureText: true,
            ),
            _ProfileField(
              label: 'Confirmer',
              controller: _confirmPasswordController,
              obscureText: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _savingPassword ? null : _updatePassword,
                style: FilledButton.styleFrom(
                  backgroundColor: _AdminColors.tealSoft,
                  foregroundColor: _AdminColors.text,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                ),
                child: Text(
                  _savingPassword
                      ? 'Mise à jour...'
                      : 'Mettre à jour le mot de passe',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(30, 30, 30, 28),
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
        Text(
          title,
          style: const TextStyle(
            color: _AdminColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(
            color: _AdminColors.muted,
            fontSize: 17,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 26),
        ...children,
      ],
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.label,
    required this.controller,
    this.enabled = true,
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _AdminColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFF5F7F7),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _AdminColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _AdminColors.border),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: _AdminColors.border),
            ),
          ),
        ),
      ],
    ),
  );
}

String _appointmentDate(Map<String, dynamic> item) =>
    item['date_heure']?.toString() ?? item['date']?.toString() ?? '';
