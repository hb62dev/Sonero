import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';

class AuthDialog extends StatefulWidget {
  const AuthDialog({super.key});

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;
  
  // Login Controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  
  // Register Controllers
  final _regNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  
  bool _isLoading = false;
  String _errorMessage = '';
  String _successMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    super.dispose();
  }

  void _clearMessages() {
    setState(() {
      _errorMessage = '';
      _successMessage = '';
    });
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailCtrl.text.trim();
    final pass = _loginPassCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Por favor, llena todos los campos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final settings = context.read<SettingsProvider>();
      await settings.loginUser(email, pass);
      setState(() {
        _successMessage = 'Sesión iniciada correctamente.';
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('ApiException(404):', '').replaceAll('ApiException(401):', '').trim();
        if (_errorMessage.isEmpty) _errorMessage = 'Error de conexión.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRegister() async {
    final name = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass = _regPassCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Por favor, llena todos los campos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final settings = context.read<SettingsProvider>();
      await settings.registerUser(name, email, pass);
      setState(() {
        _successMessage = 'Registro completado e inicio de sesión exitoso.';
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('ApiException(400):', '').trim();
        if (_errorMessage.isEmpty) _errorMessage = 'Error al registrar usuario.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSync() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      final settings = context.read<SettingsProvider>();
      await settings.loginWithGoogle();
      setState(() {
        _successMessage = 'Sincronizado con Google con éxito.';
      });
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final settings = context.watch<SettingsProvider>();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Container(
          width: 460, // Slightly wider to give tabs more breathing room
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => colors.gradient.createShader(bounds),
                      child: const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sincronizar Cuenta',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Conecta tus datos entre dispositivos',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // TabBar - Styled to fit cleanly
              TabBar(
                controller: _tabController,
                dividerColor: colors.border,
                indicatorColor: Theme.of(context).colorScheme.primary,
                labelColor: colors.textPrimary,
                unselectedLabelColor: colors.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12.5),
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: (index) {
                  setState(() {
                    _activeTabIndex = index;
                  });
                  _clearMessages();
                },
                tabs: const [
                  Tab(text: 'Entrar'),
                  Tab(text: 'Registrarse'),
                  Tab(text: 'Google Sync'),
                ],
              ),

              // Dynamic Height Content Area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Alert Messages
                      if (_errorMessage.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: colors.error, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(color: colors.error, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_successMessage.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: colors.success, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _successMessage,
                                  style: TextStyle(color: colors.success, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Switch pages dynamically with smooth cross-fade animation
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SizeTransition(
                              sizeFactor: animation,
                              axisAlignment: -1.0,
                              child: child,
                            ),
                          );
                        },
                        child: _activeTabIndex == 0
                            ? _buildLoginTab(colors)
                            : _activeTabIndex == 1
                                ? _buildRegisterTab(colors)
                                : _buildGoogleSyncTab(colors, settings),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTab(SoneroColors colors) {
    return Column(
      key: const ValueKey('login_tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          controller: _loginEmailCtrl,
          label: 'Correo Electrónico',
          hint: 'ejemplo@correo.com',
          icon: Icons.email_outlined,
          colors: colors,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _loginPassCtrl,
          label: 'Contraseña',
          hint: '••••••••',
          icon: Icons.lock_outline,
          obscure: true,
          colors: colors,
          onSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Entrar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterTab(SoneroColors colors) {
    return Column(
      key: const ValueKey('register_tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField(
          controller: _regNameCtrl,
          label: 'Nombre completo',
          hint: 'Pedro Pérez',
          icon: Icons.person_outline,
          colors: colors,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _regEmailCtrl,
          label: 'Correo Electrónico',
          hint: 'pedro@gmail.com',
          icon: Icons.email_outlined,
          colors: colors,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _regPassCtrl,
          label: 'Contraseña',
          hint: 'Mínimo 6 caracteres',
          icon: Icons.lock_outline,
          obscure: true,
          colors: colors,
          onSubmitted: (_) => _handleRegister(),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            child: _isLoading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Crear Cuenta', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSyncTab(SoneroColors colors, SettingsProvider settings) {
    return Column(
      key: const ValueKey('google_sync_tab'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        Icon(
          Icons.account_circle,
          size: 56,
          color: colors.textSecondary.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        if (!settings.hasGoogleCredentials) ...[
          Text(
            'Credenciales de Google no configuradas',
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Para habilitar la sincronización real con Google, debes agregar tu Client ID y Client Secret en la pestaña de Ajustes de la barra lateral.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
        ] else ...[
          Text(
            'Sincroniza tus datos de Sonero con tu cuenta oficial de Google.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.border),
                foregroundColor: colors.textPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                height: 18,
                errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
              ),
              label: _isLoading
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Sincronizar con Google',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
              onPressed: _isLoading ? null : _handleGoogleSync,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    required SoneroColors colors,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: colors.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, size: 16, color: colors.textSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: colors.bg.withValues(alpha: 0.5),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}
