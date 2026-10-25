import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLogin, this.lastUserName, super.key});

  /// Prefilled user name (last login on this device).
  final String? lastUserName;

  final Future<String?> Function(String userName, String password) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _userController = TextEditingController(
    text: widget.lastUserName ?? '',
  );
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Settings load after the first frame: fill in only an untouched field.
    final last = widget.lastUserName;
    if (last != null && _userController.text.isEmpty) {
      _userController.text = last;
    }
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          // Scrolls when the keyboard leaves too little room (landscape).
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 54,
                          width: 86,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: rangerGreen.withValues(alpha: 0.8),
                            ),
                          ),
                          child: Image.asset(pmcLogoAsset, fit: BoxFit.contain),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'FIRST PRIVATE MILITARY COMPANY',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _userController,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Uživatel',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      enabled: !_submitting,
                      obscureText: _obscurePassword,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Heslo',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Zobrazit heslo'
                              : 'Skrýt heslo',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: dangerRed,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: rangerGreen,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        _submitting ? Icons.hourglass_top : Icons.login,
                      ),
                      label: Text(_submitting ? 'Ověřuji' : 'Přihlásit'),
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

  Future<void> _submit() async {
    final userName = _userController.text.trim();
    if (userName.isEmpty) {
      setState(() => _errorMessage = 'Zadej uživatele.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final error = await widget.onLogin(userName, _passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _errorMessage = error;
    });
  }
}
