import 'package:flutter/material.dart';

import '../../data/media_repository.dart';
import '../../models/app_profile.dart';
import '../app_theme.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.repository,
    required this.onAuthenticated,
  });
  final MediaRepository repository;
  final ValueChanged<AppProfile> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = _register
          ? await widget.repository.registerLocalAccount(
              name: _name.text,
              email: _email.text,
              password: _password.text,
            )
          : await widget.repository.loginLocalAccount(
              email: _email.text,
              password: _password.text,
            );
      widget.onAuthenticated(profile);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst(
            'Invalid argument(s): ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _guest() async {
    setState(() => _loading = true);
    try {
      widget.onAuthenticated(await widget.repository.continueAsGuest());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 36,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.local_movies_outlined,
                        color: AppColors.accent,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Кадроскоп',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _register ? 'Создать профиль' : 'Войти',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Профиль и пароль пока хранятся только в локальной SQLite-базе этого устройства.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 22),
                  if (_register) ...[
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Имя'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.coral),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    child: Text(_register ? 'Зарегистрироваться' : 'Войти'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                    child: Text(
                      _register
                          ? 'Уже есть локальный профиль? Войти'
                          : 'Создать локальный профиль',
                    ),
                  ),
                  const Divider(height: 28),
                  OutlinedButton(
                    onPressed: _loading ? null : _guest,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('Продолжить без аккаунта'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
