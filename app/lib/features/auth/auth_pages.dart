// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';

typedef AuthLoginSubmit =
    Future<void> Function({
      required String identifier,
      required String password,
      required bool rememberDevice,
    });

typedef AuthRegisterSubmit =
    Future<void> Function({
      required String displayName,
      required String identifier,
      required String password,
      required bool acceptedTerms,
    });

typedef GuestEntrySubmit = Future<void> Function();

class AuthLoginPage extends StatefulWidget {
  const AuthLoginPage({
    super.key,
    required this.onSubmit,
    required this.onSwitchToRegister,
    required this.onContinueAsGuest,
    this.errorMessage,
  });

  final AuthLoginSubmit onSubmit;
  final VoidCallback onSwitchToRegister;
  final GuestEntrySubmit onContinueAsGuest;
  final String? errorMessage;

  @override
  State<AuthLoginPage> createState() => _AuthLoginPageState();
}

class _AuthLoginPageState extends State<AuthLoginPage> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberDevice = true;
  bool _submitting = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onSubmit(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
        rememberDevice: _rememberDevice,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _continueAsGuest() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onContinueAsGuest();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const PageStorageKey<String>('auth-login-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surface,
                  child: Icon(
                    Icons.shopping_bag_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Junk Mart',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Secure access for buyers and sellers',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                EditorialPill(
                  label: 'Auth',
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 18),
            EditorialImagePlaceholder(
              label: 'Junk Mart access',
              subtitle: 'Sign in to continue your demo journey.',
              badge: 'Secure login',
              height: 204,
              borderRadius: 30,
              accentColor: AppColors.accent,
            ),
            const SizedBox(height: 16),
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Use the phone or email address you registered with. Sign in to manage orders, chats, and listings.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: widget.errorMessage!),
            ],
            const SizedBox(height: 18),
            _AuthInputField(
              controller: _identifierController,
              label: 'Phone or email',
              hintText: 'you@example.com or 138 0000 0000',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _passwordController,
              label: 'Password',
              hintText: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _rememberDevice,
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        _rememberDevice = value ?? false;
                      });
                    },
              title: const Text('Remember this device'),
              subtitle: Text(
                'Keeps the demo session active until you sign out.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.accentDeep,
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Signing in...' : 'Sign in'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : _continueAsGuest,
              child: Text(_submitting ? 'Please wait...' : 'Continue as guest'),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('New here?', style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: _submitting ? null : widget.onSwitchToRegister,
                  child: const Text('Create account'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _AuthInfoCard(
              title: 'What happens after sign in',
              body:
                  'Your profile, messages, orders, and sell drafts all use the same user identity.',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class AuthRegisterPage extends StatefulWidget {
  const AuthRegisterPage({
    super.key,
    required this.onSubmit,
    required this.onSwitchToLogin,
    this.errorMessage,
  });

  final AuthRegisterSubmit onSubmit;
  final VoidCallback onSwitchToLogin;
  final String? errorMessage;

  @override
  State<AuthRegisterPage> createState() => _AuthRegisterPageState();
}

class _AuthRegisterPageState extends State<AuthRegisterPage> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _acceptedTerms = true;
  bool _submitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onSubmit(
        displayName: _displayNameController.text.trim(),
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
        acceptedTerms: _acceptedTerms,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          key: const PageStorageKey<String>('auth-register-list'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                EditorialRoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: widget.onSwitchToLogin,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create your account',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Join to post items, track orders, and message sellers.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                EditorialPill(
                  label: 'Join',
                  backgroundColor: AppColors.surfaceSoft,
                  foregroundColor: AppColors.text,
                ),
              ],
            ),
            const SizedBox(height: 18),
            EditorialImagePlaceholder(
              label: 'Open a new account',
              subtitle: 'Your profile and listings are created together.',
              badge: 'Register',
              height: 204,
              borderRadius: 30,
              accentColor: AppColors.surfaceRaised,
            ),
            const SizedBox(height: 16),
            Text(
              'Build your profile',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Create a seller-ready profile once. The backend should issue the user record, profile snapshot, and login session together.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: widget.errorMessage!),
            ],
            const SizedBox(height: 18),
            _AuthInputField(
              controller: _displayNameController,
              label: 'Display name',
              hintText: 'How your name appears in the app',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _identifierController,
              label: 'Phone or email',
              hintText: 'Primary sign-in identifier',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _passwordController,
              label: 'Password',
              hintText: 'Create a password',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _confirmPasswordController,
              label: 'Confirm password',
              hintText: 'Repeat your password',
              icon: Icons.lock_reset_outlined,
              obscureText: true,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _acceptedTerms,
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        _acceptedTerms = value ?? false;
                      });
                    },
              title: const Text('I agree to the terms and privacy policy'),
              subtitle: Text(
                'The consent record is stored alongside the account.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.accentDeep,
            ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: (_submitting || !_acceptedTerms) ? null : _submit,
              child: Text(
                _submitting ? 'Creating account...' : 'Create account',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : widget.onSwitchToLogin,
              child: const Text('Back to sign in'),
            ),
            const SizedBox(height: 14),
            const _AuthInfoCard(
              title: 'Database closure',
              body:
                  'Registration should create the user row, profile row, consent row, and session row in one logical flow.',
              icon: Icons.data_object_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthInputField extends StatelessWidget {
  const _AuthInputField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
              hintText: hintText,
              fillColor: Colors.transparent,
              filled: false,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthInfoCard extends StatelessWidget {
  const _AuthInfoCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1AE85D5D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x33E85D5D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFE85D5D),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
