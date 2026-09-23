part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.token,
    required this.role,
    required this.displayName,
    this.patientId,
  });

  final String token;
  final String role;
  final String displayName;
  final String? patientId;

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
        consultations: const [],
        prescriptions: const [],
      );
    } catch (_) {
      return _AdminSnapshot(
        patients: await _loadLocalPatients(),
        appointments: await _loadLocalAppointments(),
        consultations: const [],
        prescriptions: const [],
      );
    }
  }

  List<Map<String, dynamic>> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    final values = decoded is Map<String, dynamic>
        ? decoded['data'] ?? decoded['items'] ?? []
        : decoded;
    return values is List
        ? values.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _loadLocalPatients() async {
    try {
      return await LocalDatabase.instance.getPatients();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _loadLocalAppointments() async {
    try {
      return await LocalDatabase.instance.getRendezVous();
    } catch (_) {
      return const [];
    }
  }

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
        return AppointmentsPage(
          token: widget.token,
          role: widget.role,
          patientId: widget.patientId,
        );
      case 2:
        return _SettingsPage(token: widget.token);
      case 3:
        return widget.role.toLowerCase() == 'admin' ||
                widget.role.toLowerCase() == 'secretaire'
            ? _SettingsPage(token: widget.token)
            : ConsultationsFeaturePage(
                token: widget.token,
                canCreate: widget.role.toLowerCase() != 'patient',
              );
      case 4:
        return _DoctorsPage(token: widget.token);
      case 5:
        return _ProfilePage(
          token: widget.token,
          displayName: widget.displayName,
          role: widget.role,
        );
      case 6:
        return widget.role.toLowerCase() == 'admin' ||
                widget.role.toLowerCase() == 'infirmier' ||
                widget.role.toLowerCase() == 'secretaire'
            ? _SettingsPage(token: widget.token)
            : PrescriptionsPage(token: widget.token, canCreate: false);
      case 7:
        return PatientsPage(token: widget.token, role: widget.role);
      case 8:
        return _SettingsPage(token: widget.token);
      default:
        return widget.role.toLowerCase() == 'patient'
            ? _PatientDashboard(
                future: _dashboardFuture,
                displayName: widget.displayName,
                onAppointments: () => _select(1),
                onRetry: () =>
                    setState(() => _dashboardFuture = _loadDashboard()),
              )
            : widget.role.toLowerCase() == 'medecin' ||
                  widget.role.toLowerCase() == 'infirmier'
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
                onPatients: () => _select(7),
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
    return FutureBuilder<_AdminSnapshot>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
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
              : widget.role.toLowerCase() == 'medecin' ||
                    widget.role.toLowerCase() == 'infirmier'
              ? _DoctorDrawer(
                  selectedIndex: _selectedIndex,
                  displayName: widget.displayName,
                  showPrescriptions: widget.role.toLowerCase() == 'medecin',
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
                            3 => 'Consultations',
                            6 => 'Ordonnances',
                            7 => 'Patients',
                            8 => 'Paramètres',
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
                  showMedical:
                      widget.role.toLowerCase() == 'medecin' ||
                      widget.role.toLowerCase() == 'infirmier',
                  showPrescriptions: widget.role.toLowerCase() == 'medecin',
                  onSelect: _select,
                  onLogout: _logout,
                ),
              Expanded(child: _content()),
            ],
          ),
        );
      },
    );
  }
}

class _AdminSnapshot {
  const _AdminSnapshot({
    required this.patients,
    required this.appointments,
    required this.consultations,
    required this.prescriptions,
  });
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> consultations;
  final List<Map<String, dynamic>> prescriptions;
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
    this.showClose = false,
    this.showMedical = false,
    this.showPrescriptions = false,
  });
  final int selectedIndex;
  final String displayName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final bool showClose;
  final bool showMedical;
  final bool showPrescriptions;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, int)>[
      (Icons.grid_view_rounded, 'Tableau de bord', 0),
      (Icons.people_alt_rounded, 'Patients', 7),
      (Icons.calendar_month_outlined, 'Rendez-vous', 1),
      if (showMedical) (Icons.medical_information_outlined, 'Consultations', 3),
      if (showPrescriptions) (Icons.receipt_long_outlined, 'Ordonnances', 6),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
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
                if (showClose)
                  IconButton(
                    tooltip: 'Fermer le menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: _AdminColors.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                minVerticalPadding: 10,
                leading: Icon(
                  item.$1,
                  color: selectedIndex == item.$3
                      ? _AdminColors.teal
                      : _AdminColors.muted,
                ),
                title: Text(
                  item.$2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selectedIndex == item.$3
                        ? _AdminColors.text
                        : _AdminColors.muted,
                    fontWeight: selectedIndex == item.$3
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontSize: 15,
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
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            minVerticalPadding: 10,
            leading: const Icon(
              Icons.settings_outlined,
              color: _AdminColors.muted,
            ),
            title: const Text(
              'Paramètres',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _AdminColors.muted, fontSize: 15),
            ),
            selected: selectedIndex == 8,
            selectedTileColor: _AdminColors.tealSoft,
            onTap: () => onSelect(8),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const CircleAvatar(
              radius: 22,
              backgroundColor: _AdminColors.teal,
              child: Icon(Icons.person_outline, color: Colors.white, size: 22),
            ),
            title: Text(
              displayName.isEmpty ? 'Utilisateur' : displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _AdminColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: const Text(
              'Administrateur',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _AdminColors.muted),
            ),
            trailing: const Icon(Icons.more_horiz, color: _AdminColors.muted),
            onTap: () => onSelect(5),
          ),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: const Icon(Icons.logout, color: _AdminColors.muted),
            title: const Text(
              'Se déconnecter',
              style: TextStyle(color: _AdminColors.muted, fontSize: 15),
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
        showClose: true,
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
    required this.showPrescriptions,
    required this.onSelect,
    required this.onLogout,
  });

  final int selectedIndex;
  final String displayName;
  final bool showPrescriptions;
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
            icon: Icons.people_alt_rounded,
            label: 'Patients',
            selected: selectedIndex == 7,
            onTap: () => _select(context, 7),
          ),
          _DoctorNavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Rendez-vous',
            selected: selectedIndex == 1,
            onTap: () => _select(context, 1),
          ),
          _DoctorNavItem(
            icon: Icons.medical_information_outlined,
            label: 'Consultations',
            selected: selectedIndex == 3,
            onTap: () => _select(context, 3),
          ),
          if (showPrescriptions)
            _DoctorNavItem(
              icon: Icons.receipt_long_outlined,
              label: 'Ordonnances',
              selected: selectedIndex == 6,
              onTap: () => _select(context, 6),
            ),
          const Spacer(),
          const Divider(color: _AdminColors.border),
          InkWell(
            onTap: () => _select(context, 5),
            child: Padding(
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
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: Icon(
        icon,
        color: selected ? _AdminColors.teal : _AdminColors.muted,
      ),
      title: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? _AdminColors.text : _AdminColors.muted,
          fontSize: 15,
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
            icon: Icons.calendar_month_outlined,
            label: 'Rendez-vous',
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
            icon: Icons.receipt_long_outlined,
            label: 'Ordonnances',
            selected: selectedIndex == 6,
            onTap: () => _select(context, 6),
          ),
          const Spacer(),
          const Divider(color: _AdminColors.border),
          InkWell(
            onTap: () => _select(context, 5),
            child: Padding(
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
    required this.onPatients,
    required this.onComplete,
    required this.onCancel,
    required this.onRetry,
  });
  final Future<_AdminSnapshot> future;
  final String displayName;
  final VoidCallback onAppointments;
  final VoidCallback onPatients;
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
        final todayAppointments = appointments
            .where((item) => _isTodayAppointment(item))
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
                style: TextStyle(color: _AdminColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Text(
                'Bonjour ${displayName.isEmpty ? 'Rova' : displayName},\nbienvenue.',
                style: TextStyle(
                  color: _AdminColors.text,
                  fontSize: MediaQuery.sizeOf(context).width < 600 ? 26 : 29,
                  fontWeight: FontWeight.w800,
                  height: 1.18,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Voici un aperçu de l’activité de votre centre.',
                style: TextStyle(
                  color: _AdminColors.muted,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAppointments,
                  icon: const Icon(Icons.add, size: 22),
                  label: const Text('Nouveau rendez-vous'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 42),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 700 ? 2 : 4;
                  final aspectRatio = constraints.maxWidth < 700 ? 1.35 : 1.55;
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
                        label: "Rendez-vous aujourd'hui",
                        value: '$todayAppointments',
                        onTap: onAppointments,
                      ),
                      _AdminStat(
                        icon: Icons.people_outline,
                        label: 'Patients suivis',
                        value: '${data.patients.length}',
                        onTap: onPatients,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 40),
              _AdminUpcomingAppointments(
                appointments: appointments,
                patients: data.patients,
                onTap: onAppointments,
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
    constraints: const BoxConstraints(minHeight: 118),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _AdminColors.tealSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _AdminColors.teal, size: 24),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 13,
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
                          fontSize: 26,
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

class _AdminUpcomingAppointments extends StatelessWidget {
  const _AdminUpcomingAppointments({
    required this.appointments,
    required this.patients,
    required this.onTap,
  });

  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> patients;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final upcoming = appointments
        .where((item) {
          final status = item['statut']?.toString().toLowerCase() ?? '';
          return status != 'annule' &&
              status != 'annulé' &&
              status != 'termine';
        })
        .take(2)
        .toList();
    return _DashboardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Prochains rendez-vous',
                  style: _DashboardSection.titleStyle,
                ),
              ),
              InkWell(
                onTap: onTap,
                child: const Row(
                  children: [
                    Text(
                      'Tout voir',
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
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _dashboardDateLabel(upcoming.first),
              style: const TextStyle(
                color: _AdminColors.muted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (upcoming.isEmpty)
            const Text(
              'Aucun rendez-vous à venir.',
              style: TextStyle(color: _AdminColors.muted),
            )
          else
            for (var index = 0; index < upcoming.length; index++)
              _DashboardAppointmentLine(
                appointment: upcoming[index],
                patients: patients,
                showDivider: index < upcoming.length - 1,
              ),
        ],
      ),
    );
  }
}

class _DashboardAppointmentLine extends StatelessWidget {
  const _DashboardAppointmentLine({
    required this.appointment,
    required this.patients,
    required this.showDivider,
  });

  final Map<String, dynamic> appointment;
  final List<Map<String, dynamic>> patients;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(_appointmentDate(appointment));
    final patient = patients.cast<Map<String, dynamic>?>().firstWhere(
      (item) =>
          item?['id']?.toString() == appointment['patient_id']?.toString(),
      orElse: () => null,
    );
    final patientName = patient == null
        ? appointment['patient_nom']?.toString() ?? 'Patient'
        : '${patient['prenom'] ?? ''} ${patient['nom'] ?? ''}'.trim();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 68,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date == null
                          ? '--:--'
                          : TimeOfDay.fromDateTime(date).format(context),
                      style: const TextStyle(
                        color: _AdminColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      date == null ? '--' : '${date.day} sept.',
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      appointment['motif']?.toString() ?? 'Consultation',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '♧  Dr. ${appointment['medecin_nom'] ?? 'Médecin'}',
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF9BAEB2)),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: _AdminColors.border),
      ],
    );
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.child});

  final Widget child;

  static const titleStyle = TextStyle(
    color: _AdminColors.text,
    fontSize: 20,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _AdminColors.border),
    ),
    child: child,
  );
}

String _dashboardDateLabel(Map<String, dynamic> appointment) {
  final date = DateTime.tryParse(_appointmentDate(appointment));
  if (date == null) return 'Date non renseignée';
  return '${_weekdayName(date.weekday)} ${date.day} septembre ${date.year}';
}

String _weekdayName(int weekday) => const [
  '',
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
][weekday.clamp(0, 7)];

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

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: _AdminColors.background,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Paramètres',
                    style: TextStyle(
                      color: _AdminColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gérez les réglages de base et les utilisateurs de l’application.',
                    style: TextStyle(color: _AdminColors.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  TabBar(
                    labelColor: _AdminColors.teal,
                    unselectedLabelColor: _AdminColors.muted,
                    indicatorColor: _AdminColors.teal,
                    tabs: const [
                      Tab(text: 'Paramètres de base'),
                      Tab(text: 'Utilisateurs'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.brightness_6_outlined,
                          color: _AdminColors.teal,
                        ),
                        title: const Text('Apparence'),
                        subtitle: const Text(
                          'Choisissez le thème clair ou sombre de l’application.',
                        ),
                        trailing: const _ThemeToggleButton(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.language_outlined,
                          color: _AdminColors.teal,
                        ),
                        title: Text('Langue'),
                        subtitle: Text('Français'),
                      ),
                    ),
                  ],
                ),
                _UsersPage(token: token),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
    final selectedRole = _roleFilter.toLowerCase();
    return users.where((user) {
      final name = (user['nom'] ?? user['name'] ?? '').toString();
      final login = (user['login'] ?? user['email'] ?? '').toString();
      final specialty = (user['specialite'] ?? '').toString();
      final role = (user['role'] ?? '').toString().toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          '$name $login $specialty'.toLowerCase().contains(query);
      final matchesRole =
          selectedRole == 'tous' || role == _userRoleKey(_roleFilter);
      return matchesSearch && matchesRole;
    }).toList();
  }

  String _userRoleKey(String label) => switch (label.toLowerCase()) {
    'administrateur' => 'admin',
    'médecin' => 'medecin',
    'secrétaire' => 'secretaire',
    'patient' => 'patient',
    _ => label.toLowerCase(),
  };

  Future<void> _createUser() async {
    final nameController = TextEditingController();
    final loginController = TextEditingController();
    final passwordController = TextEditingController();
    var role = 'patient';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Créer un compte'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                        ? 'Nom obligatoire'
                        : null,
                  ),
                  TextFormField(
                    controller: loginController,
                    decoration: const InputDecoration(labelText: 'Identifiant'),
                    validator: (value) =>
                        value == null || value.trim().length < 3
                        ? 'Identifiant obligatoire'
                        : null,
                  ),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                    ),
                    validator: (value) => value == null || value.length < 6
                        ? '6 caractères minimum'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Rôle'),
                    items: const [
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrateur'),
                      ),
                      DropdownMenuItem(
                        value: 'medecin',
                        child: Text('Médecin'),
                      ),
                      DropdownMenuItem(
                        value: 'infirmier',
                        child: Text('Infirmier'),
                      ),
                      DropdownMenuItem(
                        value: 'secretaire',
                        child: Text('Secrétaire'),
                      ),
                      DropdownMenuItem(
                        value: 'patient',
                        child: Text('Patient'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => role = value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final response = await http.post(
                  Uri.parse(
                    '${_LoginPageState._apiBaseUrl}/api/v1/admin/users',
                  ),
                  headers: {
                    'Authorization': 'Bearer ${widget.token}',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'nom': nameController.text.trim(),
                    'login': loginController.text.trim(),
                    'mot_de_passe': passwordController.text,
                    'role': role,
                  }),
                );
                if (!dialogContext.mounted) return;
                if (response.statusCode == 201) {
                  Navigator.pop(dialogContext, true);
                } else {
                  String detail = 'Création impossible.';
                  try {
                    detail =
                        (jsonDecode(response.body)
                                as Map<String, dynamic>)['detail']
                            ?.toString() ??
                        detail;
                  } catch (_) {}
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(detail)));
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    loginController.dispose();
    passwordController.dispose();
    if (result == true && mounted) {
      setState(() => _usersFuture = _loadUsers());
    }
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
                  Expanded(
                    child: Column(
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
                  ),
                  FilledButton.icon(
                    onPressed: _createUser,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Créer'),
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
                _UsersList(
                  users: users,
                  token: widget.token,
                  onChanged: () => setState(() => _usersFuture = _loadUsers()),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList({
    required this.users,
    required this.token,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> users;
  final String token;
  final VoidCallback onChanged;

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
            _UserListTile(
              user: users[index],
              token: token,
              onChanged: onChanged,
            ),
            if (index < users.length - 1)
              const Divider(height: 1, color: _AdminColors.border),
          ],
        ],
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  const _UserListTile({
    required this.user,
    required this.token,
    required this.onChanged,
  });

  final Map<String, dynamic> user;
  final String token;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final name = (user['nom'] ?? user['name'] ?? 'Utilisateur').toString();
    final email = (user['email'] ?? user['login'] ?? '').toString();
    final roleKey = (user['role'] ?? 'patient').toString().toLowerCase();
    final role = switch (roleKey) {
      'admin' => 'Administrateur',
      'medecin' => 'Médecin',
      'infirmier' => 'Infirmier',
      'secretaire' => 'Secrétaire',
      _ => 'Patient',
    };
    final specialty = (user['specialite'] ?? '').toString();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final isAdmin = roleKey == 'admin';
    final badgeColor = role == 'Médecin'
        ? const Color(0xFFE2F3EF)
        : role == 'Secrétaire'
        ? const Color(0xFFFFF4DF)
        : role == 'Patient'
        ? const Color(0xFFE7F0F1)
        : _AdminColors.teal;

    return InkWell(
      onTap: () => _editUser(context),
      child: Padding(
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
            if (!isAdmin)
              PopupMenuButton<String>(
                tooltip: 'Actions utilisateur',
                onSelected: (action) async {
                  final id = user['id']?.toString();
                  if (id == null) return;
                  if (action == 'deactivate') {
                    final response = await http.delete(
                      Uri.parse(
                        '${_LoginPageState._apiBaseUrl}/api/v1/admin/users/$id',
                      ),
                      headers: {'Authorization': 'Bearer $token'},
                    );
                    if (response.statusCode == 200) onChanged();
                  }
                  if (action == 'reset') {
                    if (!context.mounted) return;
                    final password = await _askForPassword(context);
                    if (password == null) return;
                    final response = await http.post(
                      Uri.parse(
                        '${_LoginPageState._apiBaseUrl}/api/v1/admin/users/$id/reset-password',
                      ),
                      headers: {
                        'Authorization': 'Bearer $token',
                        'Content-Type': 'application/json',
                      },
                      body: jsonEncode({'mot_de_passe': password}),
                    );
                    if (response.statusCode == 200 && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Mot de passe réinitialisé.'),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'reset',
                    child: Text('Réinitialiser le mot de passe'),
                  ),
                  PopupMenuItem(
                    value: 'deactivate',
                    child: Text('Désactiver le compte'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUser(BuildContext context) async {
    final nameController = TextEditingController(
      text: (user['nom'] ?? '').toString(),
    );
    final loginController = TextEditingController(
      text: (user['login'] ?? user['email'] ?? '').toString(),
    );
    final specialityController = TextEditingController(
      text: (user['specialite'] ?? '').toString(),
    );
    final orderNumberController = TextEditingController(
      text: (user['numero_ordre'] ?? '').toString(),
    );
    var role = (user['role'] ?? 'patient').toString();
    final formKey = GlobalKey<FormState>();
    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Profil de ${nameController.text}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nom complet'),
                    validator: (value) =>
                        value == null || value.trim().length < 2
                        ? 'Nom obligatoire'
                        : null,
                  ),
                  TextFormField(
                    controller: loginController,
                    decoration: const InputDecoration(labelText: 'Identifiant'),
                    validator: (value) =>
                        value == null || value.trim().length < 3
                        ? 'Identifiant obligatoire'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Rôle'),
                    items: const [
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('Administrateur'),
                      ),
                      DropdownMenuItem(
                        value: 'medecin',
                        child: Text('Médecin'),
                      ),
                      DropdownMenuItem(
                        value: 'infirmier',
                        child: Text('Infirmier'),
                      ),
                      DropdownMenuItem(
                        value: 'secretaire',
                        child: Text('Secrétaire'),
                      ),
                      DropdownMenuItem(
                        value: 'patient',
                        child: Text('Patient'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => role = value);
                    },
                  ),
                  TextFormField(
                    controller: specialityController,
                    decoration: const InputDecoration(labelText: 'Spécialité'),
                  ),
                  TextFormField(
                    controller: orderNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Numéro professionnel',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final id = user['id']?.toString();
                if (id == null || id.isEmpty) return;
                final response = await http.put(
                  Uri.parse(
                    '${_LoginPageState._apiBaseUrl}/api/v1/admin/users/$id',
                  ),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'nom': nameController.text.trim(),
                    'login': loginController.text.trim(),
                    'role': role,
                    'specialite': specialityController.text.trim(),
                    'numero_ordre': orderNumberController.text.trim(),
                  }),
                );
                if (!dialogContext.mounted) return;
                if (response.statusCode == 200) {
                  Navigator.pop(dialogContext, true);
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Modification impossible.')),
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    loginController.dispose();
    specialityController.dispose();
    orderNumberController.dispose();
    if (updated == true) onChanged();
  }
}

Future<String?> _askForPassword(BuildContext context) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nouveau mot de passe'),
      content: TextField(
        controller: controller,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Mot de passe'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Réinitialiser'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value != null && value.length >= 6 ? value : null;
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
  late final TextEditingController _addressController;
  late final TextEditingController _emergencyController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _birthDateController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _savingProfile = false;
  bool _savingPassword = false;
  String? _birthDate;
  String? _bloodGroup;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.displayName.isEmpty ? 'Utilisateur' : widget.displayName,
    );
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _addressController = TextEditingController();
    _emergencyController = TextEditingController();
    _allergiesController = TextEditingController();
    _birthDateController = TextEditingController();
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
        _birthDate = profile['date_naissance']?.toString();
        _birthDateController.text = _birthDate ?? '';
        _bloodGroup = profile['groupe_sanguin']?.toString();
        _phoneController.text = profile['telephone']?.toString() ?? '';
        _addressController.text = profile['adresse']?.toString() ?? '';
        _emergencyController.text =
            profile['contact_urgence']?.toString() ?? '';
        _allergiesController.text = profile['allergies']?.toString() ?? '';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyController.dispose();
    _allergiesController.dispose();
    _birthDateController.dispose();
    _currentPasswordController.dispose();
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
          'login': _emailController.text.trim(),
          if (widget.role.toLowerCase() == 'patient') ...{
            'date_naissance': _birthDate,
            'telephone': _phoneController.text.trim(),
            'adresse': _addressController.text.trim(),
            'contact_urgence': _emergencyController.text.trim(),
            'groupe_sanguin': _bloodGroup,
            'allergies': _allergiesController.text.trim(),
          },
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

  Future<void> _selectBirthDate() async {
    final initialDate = DateTime.tryParse(_birthDate ?? '') ?? DateTime(1990);
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      initialDate: initialDate,
    );
    if (selected == null || !mounted) return;
    final value = selected.toIso8601String().substring(0, 10);
    setState(() {
      _birthDate = value;
      _birthDateController.text = value;
    });
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
        body: jsonEncode({
          'ancien_mot_de_passe': _currentPasswordController.text,
          'nouveau_mot_de_passe': _newPasswordController.text,
        }),
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
    final isPatient = widget.role.toLowerCase() == 'patient';
    final roleLabel = switch (widget.role.toLowerCase()) {
      'admin' => 'Administrateur',
      'medecin' => 'Médecin',
      'infirmier' => 'Infirmier',
      'secretaire' => 'Secrétaire',
      _ => 'Patient',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: _AdminColors.teal,
              child: Text(
                _initials(_nameController.text),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isPatient ? 'Dossier patient' : 'Profil utilisateur',
              style: const TextStyle(color: _AdminColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Text(
              _nameController.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _AdminColors.text,
                fontSize: 29,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isPatient && _birthDate != null
                  ? '${_patientAge(_birthDate) ?? 'Âge non renseigné'} ans · $roleLabel'
                  : '$roleLabel · ${_emailController.text}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 34),
        _ProfileSection(
          title: 'Informations personnelles',
          description: 'Modifiez votre nom complet et votre identifiant.',
          children: [
            _ProfileField(label: 'Nom complet', controller: _nameController),
            _ProfileField(
              label: 'Identifiant',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
            ),
            if (isPatient) ...[
              _ProfileField(
                label: 'Téléphone',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
              ),
              _ProfileField(
                label: 'Date de naissance',
                controller: _birthDateController,
                readOnly: true,
                onTap: _selectBirthDate,
                suffixIcon: Icons.calendar_today_outlined,
              ),
              _ProfileField(
                label: 'Adresse',
                controller: _addressController,
                maxLines: 2,
              ),
              DropdownButtonFormField<String>(
                initialValue: _bloodGroup?.isEmpty == true ? null : _bloodGroup,
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
                onChanged: (value) => setState(() => _bloodGroup = value),
              ),
              _ProfileField(
                label: "Contact d'urgence",
                controller: _emergencyController,
                keyboardType: TextInputType.phone,
              ),
              _ProfileField(
                label: 'Allergies connues',
                controller: _allergiesController,
                maxLines: 3,
              ),
            ],
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
          description:
              'Changez votre mot de passe avec votre mot de passe actuel.',
          children: [
            _ProfileField(
              label: 'Mot de passe actuel',
              controller: _currentPasswordController,
              obscureText: true,
            ),
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
    this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final IconData? suffixIcon;
  final int maxLines;

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
          obscureText: obscureText,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
            filled: true,
            fillColor: Colors.white,
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

bool _isTodayAppointment(Map<String, dynamic> item) {
  final date = DateTime.tryParse(_appointmentDate(item));
  if (date == null) return false;
  final today = DateTime.now();
  return date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;
}
