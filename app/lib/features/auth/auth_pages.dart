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

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
        rememberDevice: _rememberDevice,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    if (_submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onContinueAsGuest();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
                        '买家和卖家的安全登录',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                EditorialPill(
                  label: '登录',
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('欢迎回来', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '使用注册时的手机号或邮箱登录，管理订单、消息和商品。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: widget.errorMessage!),
            ],
            const SizedBox(height: 20),
            _AuthInputField(
              controller: _identifierController,
              label: '手机号或邮箱',
              hintText: '请输入手机号或邮箱',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _passwordController,
              label: '密码',
              hintText: '请输入密码',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _rememberDevice,
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() => _rememberDevice = value ?? false);
                      },
                title: const Text('记住本设备'),
                subtitle: Text(
                  '保持登录状态，直到手动退出。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.accentDeep,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? '登录中...' : '登录'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : _continueAsGuest,
              child: Text(_submitting ? '请稍候...' : '游客模式'),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('还没有账号？', style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                  onPressed: _submitting ? null : widget.onSwitchToRegister,
                  child: const Text('立即注册'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _AuthInfoCard(
              title: '登录后可使用',
              body: '你的个人资料、订单、聊天记录和发布内容都会关联到同一个账号。',
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
      ).showSnackBar(const SnackBar(content: Text('两次输入的密码不一致')));
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        displayName: _displayNameController.text.trim(),
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
        acceptedTerms: _acceptedTerms,
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
                        '注册账号',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '注册后可以发布商品、查看订单并与买家卖家沟通。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                EditorialPill(
                  label: '注册',
                  backgroundColor: AppColors.surfaceSoft,
                  foregroundColor: AppColors.text,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('完善账号信息', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            Text(
              '创建账号后即可开始发布商品和浏览 3D 二手市场。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: widget.errorMessage!),
            ],
            const SizedBox(height: 20),
            _AuthInputField(
              controller: _displayNameController,
              label: '昵称',
              hintText: '输入展示昵称',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _identifierController,
              label: '手机号或邮箱',
              hintText: '输入手机号或邮箱',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _passwordController,
              label: '密码',
              hintText: '设置登录密码',
              icon: Icons.lock_outline_rounded,
              obscureText: true,
            ),
            const SizedBox(height: 12),
            _AuthInputField(
              controller: _confirmPasswordController,
              label: '确认密码',
              hintText: '再次输入密码',
              icon: Icons.lock_reset_outlined,
              obscureText: true,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acceptedTerms,
                onChanged: _submitting
                    ? null
                    : (value) {
                        setState(() => _acceptedTerms = value ?? false);
                      },
                title: const Text('我已阅读并同意服务条款和隐私政策'),
                subtitle: Text(
                  '你的同意记录会与账号一起保存。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.accentDeep,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: (_submitting || !_acceptedTerms) ? null : _submit,
              child: Text(_submitting ? '注册中...' : '创建账号'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _submitting ? null : widget.onSwitchToLogin,
              child: const Text('返回登录'),
            ),
            const SizedBox(height: 14),
            const _AuthInfoCard(
              title: '账号安全',
              body: '注册后会同时创建你的用户资料和个人主页，方便后续发布和交易。',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hintText,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
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
