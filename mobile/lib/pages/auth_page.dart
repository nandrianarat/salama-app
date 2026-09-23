part of '../main.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _openLogin(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _ThemeToggleButton(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 34),
                    decoration: BoxDecoration(
                      color: HadColors.sageSoft,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(88),
                        bottomRight: Radius.circular(88),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: HadColors.sage.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.eco_rounded,
                            size: 38,
                            color: HadColors.sage,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Rova.',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: HadColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'Bienvenue chez Rova',
                    textAlign: TextAlign.center,
                    style: HadText.heroTitle,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'L\'expertise des soins complexes et coordonnés que ce soit à domicile ou en centre de soins.',
                    textAlign: TextAlign.center,
                    style: HadText.bodySoft,
                  ),
                  const SizedBox(height: 28),
                  _WelcomeRoleCard(
                    icon: Icons.business_rounded,
                    title: 'Qui sommes-nous ?',
                    description:
                        'Une société privée créée en 2008 par le Docteur Elisabeth HUBERT, ancien médecin généraliste et actuelle présidente de la FNEHAD.',
                  ),
                  const SizedBox(height: 14),
                  _WelcomeRoleCard(
                    icon: Icons.flag_rounded,
                    title: 'Nos missions ?',
                    description:
                        'Développer des offres d\'hospitalisation à domicile pour des personnes de tous âges, atteints de pathologies complexes.',
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: () => _openLogin(context),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Se connecter'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      foregroundColor: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Veuillez vous connecter pour accéder à votre espace personnel.',
                    textAlign: TextAlign.center,
                    style: HadText.bodySoft,
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

class _WelcomeRoleCard extends StatelessWidget {
  const _WelcomeRoleCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: HadColors.claySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: HadColors.clay),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HadText.sectionTitle),
                const SizedBox(height: 5),
                Text(description, style: HadText.bodySoft),
              ],
            ),
          ),
        ],
      ),
    );

    return Card(child: content);
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
  final _nameController = TextEditingController();
  final _registerLoginController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerPasswordConfirmationController = TextEditingController();
  final _registerNameFocus = FocusNode();
  final _registerLoginFocus = FocusNode();
  final _registerPasswordFocus = FocusNode();
  final _registerConfirmationFocus = FocusNode();
  bool _loading = false;
  bool _showPassword = false;
  bool _isRegisterMode = false;
  String _selectedRole = 'patient';
  String? _error;

  // Android emulator: 10.0.2.2 points to the development computer.
  // Physical Android devices need the LAN IP of the machine hosting the backend.
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static String get _apiBaseUrl => _configuredApiBaseUrl.isNotEmpty
      ? _configuredApiBaseUrl
      : kIsWeb
      ? 'http://localhost:8001'
      //  : defaultTargetPlatform == TargetPlatform.android
      //   ? 'http://10.0.2.2:8001'
      : 'http://192.168.1.65:8001';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _registerLoginController.dispose();
    _registerPasswordController.dispose();
    _registerPasswordConfirmationController.dispose();
    _registerNameFocus.dispose();
    _registerLoginFocus.dispose();
    _registerPasswordFocus.dispose();
    _registerConfirmationFocus.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final login = _registerLoginController.text.trim();
    final password = _registerPasswordController.text;
    final passwordConfirmation = _registerPasswordConfirmationController.text;

    if (name.isEmpty || login.isEmpty || password.isEmpty) {
      setState(
        () => _error =
            'Veuillez ajouter vos informations avant de créer un compte',
      );
      return;
    }
    if (passwordConfirmation.isEmpty) {
      setState(() => _error = 'Veuillez confirmer votre mot de passe');
      return;
    }
    if (passwordConfirmation != password) {
      setState(() => _error = 'Les mots de passe ne correspondent pas');
      return;
    }
    if (password.length < 6) {
      setState(
        () => _error =
            'Votre mot de passe doit contenir au moins 6 caractères minimum',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nom': _nameController.text.trim(),
          'login': _registerLoginController.text.trim(),
          'mot_de_passe': _registerPasswordController.text,
          'role': _selectedRole,
        }),
      );
      if (!mounted) return;
      if (response.statusCode == 201) {
        setState(() {
          _isRegisterMode = false;
          _usernameController.text = _registerLoginController.text.trim();
          _error = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compte créé. Vous pouvez vous connecter.'),
          ),
        );
      } else {
        String? detail;
        try {
          detail =
              (jsonDecode(response.body) as Map<String, dynamic>)['detail']
                  as String?;
        } catch (_) {
          detail = null;
        }
        setState(
          () => _error =
              detail ??
              (response.statusCode == 409
                  ? 'Cet identifiant est déjà utilisé.'
                  : 'Inscription impossible. Vérifiez les informations.'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Serveur inaccessible. Réessayez plus tard.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty && password.isEmpty) {
      setState(
        () => _error =
            'Veuillez entrer votre identifiant et votre mot de passe avant de vous connecter',
      );
      return;
    }
    if (username.isEmpty) {
      setState(() => _error = 'Votre identifiant est incorrect');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Veuillez ajouter votre mot de passe');
      return;
    }
    if (password.length < 6) {
      setState(
        () => _error =
            'Votre mot de passe doit contenir au moins 6 caractères minimum',
      );
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
        final role =
            (data['user'] as Map<String, dynamic>?)?['role'] as String? ??
            'patient';
        await _secureStorage.write(
          key: _tokenKey,
          value: data['access_token'] as String,
        );
        await _secureStorage.write(key: _roleKey, value: role);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              token: data['access_token'] as String,
              role: role,
              patientId: (data['user'] as Map<String, dynamic>?)?['patient_id']
                  ?.toString(),
              displayName:
                  (data['user'] as Map<String, dynamic>?)?['nom'] as String? ??
                  'Administrateur',
            ),
          ),
        );
      } else {
        String? detail;
        try {
          detail =
              (jsonDecode(response.body) as Map<String, dynamic>)['detail']
                  as String?;
        } catch (_) {
          detail = null;
        }
        setState(() => _error = detail ?? 'Votre identifiant est incorrect');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Connexion impossible. Vérifiez le serveur et le réseau.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForgotPassword() async {
    final emailController = TextEditingController(
      text: _usernameController.text.trim(),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mot de passe oublié ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indiquez votre identifiant. Un administrateur Rova pourra réinitialiser votre accès.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email ou identifiant',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Votre demande a été transmise à l’administrateur.',
                  ),
                ),
              );
            },
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
    emailController.dispose();
  }

  // ignore: unused_element
  Future<void> _showRegister() async {
    final nameController = TextEditingController();
    final loginController = TextEditingController();
    final passwordController = TextEditingController();
    var selectedRole = 'patient';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Créer un compte'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Demandez votre accès professionnel à l’équipe Rova.'),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loginController,
                decoration: const InputDecoration(
                  labelText: 'Email ou identifiant',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe souhaité',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setDialogState) =>
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Rôle',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'patient',
                          child: Text('Patient'),
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
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedRole = value);
                        }
                      },
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  loginController.text.trim().isEmpty ||
                  passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Veuillez compléter vos informations pour continuer.',
                    ),
                  ),
                );
                return;
              }
              try {
                final response = await http.post(
                  Uri.parse('$_apiBaseUrl/api/v1/auth/register'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'nom': nameController.text.trim(),
                    'login': loginController.text.trim(),
                    'mot_de_passe': passwordController.text,
                    'role': selectedRole,
                  }),
                );
                if (!mounted || !dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      response.statusCode == 201
                          ? 'Compte créé. Vous pouvez vous connecter.'
                          : response.statusCode == 409
                          ? 'Cet identifiant est déjà utilisé.'
                          : 'Inscription impossible. Vérifiez les informations.',
                    ),
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Serveur inaccessible. Réessayez plus tard.'),
                  ),
                );
              }
            },
            child: const Text('Créer mon compte'),
          ),
        ],
      ),
    );
    nameController.dispose();
    loginController.dispose();
    passwordController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;
    final horizontalPadding = compact ? 16.0 : 24.0;
    final cardPadding = compact ? 16.0 : 24.0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(top: 12, right: 18, child: _ThemeToggleButton()),
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 28 : 42,
                  horizontalPadding,
                  28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Column(
                    children: [
                      _RovaLogo(size: compact ? 56 : 64),
                      SizedBox(height: compact ? 10 : 14),
                      Text(
                        'Rova.',
                        style: TextStyle(
                          fontSize: compact ? 27 : 32,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Être soigné à la maison.',
                        style: HadText.bodySoft,
                      ),
                      SizedBox(height: compact ? 20 : 30),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                height: 52,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF293238)
                                      : const Color(0xFFF2F1EB),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) => Stack(
                                    children: [
                                      AnimatedAlign(
                                        alignment: _isRegisterMode
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOutCubic,
                                        child: SizedBox(
                                          width: constraints.maxWidth / 2,
                                          height: double.infinity,
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).cardColor,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x14000000),
                                                  blurRadius: 4,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox.expand(
                                              child: TextButton(
                                                onPressed: _loading
                                                    ? null
                                                    : () => setState(() {
                                                        _isRegisterMode = false;
                                                        _error = null;
                                                      }),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      _isRegisterMode
                                                      ? HadColors.inkSoft
                                                      : HadColors.ink,
                                                  minimumSize: Size.zero,
                                                  padding: EdgeInsets.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: const Text('Connexion'),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: SizedBox.expand(
                                              child: TextButton(
                                                onPressed: _loading
                                                    ? null
                                                    : () => setState(() {
                                                        _isRegisterMode = true;
                                                        _error = null;
                                                      }),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      _isRegisterMode
                                                      ? HadColors.ink
                                                      : HadColors.inkSoft,
                                                  minimumSize: Size.zero,
                                                  padding: EdgeInsets.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: const Text(
                                                  'Créer un compte',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                transitionBuilder: (child, animation) =>
                                    SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(.12, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                child: _isRegisterMode
                                    ? Column(
                                        key: const ValueKey('register'),
                                        children: [
                                          TextField(
                                            controller: _nameController,
                                            focusNode: _registerNameFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onSubmitted: (_) => FocusScope.of(
                                              context,
                                            ).requestFocus(_registerLoginFocus),
                                            decoration: const InputDecoration(
                                              labelText: 'Nom complet',
                                              prefixIcon: Icon(
                                                Icons.person_outline_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextField(
                                            controller:
                                                _registerLoginController,
                                            focusNode: _registerLoginFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onSubmitted: (_) =>
                                                FocusScope.of(
                                                  context,
                                                ).requestFocus(
                                                  _registerPasswordFocus,
                                                ),
                                            decoration: const InputDecoration(
                                              labelText: 'Email ou identifiant',
                                              prefixIcon: Icon(
                                                Icons.mail_outline_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextField(
                                            controller:
                                                _registerPasswordController,
                                            focusNode: _registerPasswordFocus,
                                            textInputAction:
                                                TextInputAction.next,
                                            onSubmitted: (_) =>
                                                FocusScope.of(
                                                  context,
                                                ).requestFocus(
                                                  _registerConfirmationFocus,
                                                ),
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Mot de passe',
                                              hintText: '6 caractères minimum',
                                              prefixIcon: Icon(
                                                Icons.lock_outline_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextField(
                                            controller:
                                                _registerPasswordConfirmationController,
                                            focusNode:
                                                _registerConfirmationFocus,
                                            textInputAction:
                                                TextInputAction.done,
                                            onSubmitted: (_) => _register(),
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Confirmer le mot de passe',
                                              prefixIcon: Icon(
                                                Icons.lock_reset_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          DropdownButtonFormField<String>(
                                            initialValue: _selectedRole,
                                            decoration: const InputDecoration(
                                              labelText: 'Rôle',
                                              prefixIcon: Icon(
                                                Icons.badge_outlined,
                                              ),
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'patient',
                                                child: Text('Patient'),
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
                                            ],
                                            onChanged: (value) {
                                              if (value != null) {
                                                setState(
                                                  () => _selectedRole = value,
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      )
                                    : Column(
                                        key: const ValueKey('login'),
                                        children: [
                                          TextField(
                                            controller: _usernameController,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: const InputDecoration(
                                              labelText: 'Email ou identifiant',
                                              prefixIcon: Icon(
                                                Icons.mail_outline_rounded,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          TextField(
                                            controller: _passwordController,
                                            obscureText: !_showPassword,
                                            onSubmitted: (_) => _login(),
                                            decoration: InputDecoration(
                                              labelText: 'Mot de passe',
                                              prefixIcon: const Icon(
                                                Icons.lock_outline_rounded,
                                              ),
                                              suffixIcon: IconButton(
                                                tooltip:
                                                    'Afficher ou masquer le mot de passe',
                                                onPressed: () => setState(
                                                  () => _showPassword =
                                                      !_showPassword,
                                                ),
                                                icon: Icon(
                                                  _showPassword
                                                      ? Icons
                                                            .visibility_off_outlined
                                                      : Icons
                                                            .visibility_outlined,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton(
                                              onPressed: _loading
                                                  ? null
                                                  : _showForgotPassword,
                                              child: const Text(
                                                'Mot de passe oublié ?',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: Color(0xFFE84860),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: _loading
                                    ? null
                                    : (_isRegisterMode ? _register : _login),
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _isRegisterMode
                                            ? Icons.person_add_alt_1_rounded
                                            : Icons.arrow_forward_rounded,
                                      ),
                                label: Text(
                                  _loading
                                      ? 'Connexion en cours...'
                                      : _isRegisterMode
                                      ? 'Créer mon compte'
                                      : 'Se connecter',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'En continuant, vous acceptez nos conditions d’utilisation et notre politique de confidentialité.',
                        textAlign: TextAlign.center,
                        style: HadText.bodySoft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
