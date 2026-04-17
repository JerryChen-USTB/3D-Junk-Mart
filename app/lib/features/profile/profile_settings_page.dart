import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/session/app_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/editorial_widgets.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({
    super.key,
    required this.session,
    required this.apiClient,
    required this.accessToken,
    required this.onSave,
  });

  final AppSession session;
  final ApiClient apiClient;
  final String accessToken;
  final VoidCallback onSave;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late String _visibility;
  String? _avatarPath;
  String? _remoteAvatarUrl;
  bool _saving = false;
  bool _loadingProfile = true;

  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _birthDateCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _bioCtrl;

  String _readField(String key) =>
      widget.session.profile?[key]?.toString() ??
      widget.session.user[key]?.toString() ??
      '';

  String get _ageLabel {
    final bd = _birthDateCtrl.text.trim();
    if (bd.isEmpty) {
      return '-';
    }
    try {
      final date = DateTime.parse(bd);
      final now = DateTime.now();
      var years = now.year - date.year;
      if (now.month < date.month ||
          (now.month == date.month && now.day < date.day)) {
        years -= 1;
      }
      return '$years';
    } catch (_) {
      return '-';
    }
  }

  @override
  void initState() {
    super.initState();
    _visibility = _readField('profile_visibility');
    if (_visibility.isEmpty) {
      _visibility = 'public';
    }
    _nicknameCtrl = TextEditingController(text: _readField('display_name'));
    _birthDateCtrl = TextEditingController(text: _readField('birth_date'));
    _locationCtrl = TextEditingController(text: _readField('location'));
    _bioCtrl = TextEditingController(text: _readField('bio'));
    _remoteAvatarUrl = _resolveAvatarUrl(_readField('avatar_url'));
    _loadProfile();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _birthDateCtrl.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await widget.apiClient.getJson(
        '/users/me',
        bearerToken: widget.accessToken,
      );
      final profile = response.data;
      if (!mounted) {
        return;
      }
      setState(() {
        _nicknameCtrl.text =
            profile['display_name']?.toString() ?? _nicknameCtrl.text;
        _birthDateCtrl.text =
            profile['birth_date']?.toString() ?? _birthDateCtrl.text;
        _locationCtrl.text =
            profile['location']?.toString() ?? _locationCtrl.text;
        _bioCtrl.text = profile['bio']?.toString() ?? _bioCtrl.text;
        _visibility = profile['profile_visibility']?.toString() ?? _visibility;
        _remoteAvatarUrl = _resolveAvatarUrl(profile['avatar_url']?.toString());
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  String? _resolveAvatarUrl(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    final base = Uri.parse(widget.apiClient.baseUrl).resolve('/');
    return base.resolve(raw).toString();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image != null && mounted) {
      setState(() => _avatarPath = image.path);
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);

    try {
      if (_avatarPath != null) {
        await widget.apiClient.uploadFile(
          '/users/me/avatar',
          filePath: _avatarPath!,
          fieldName: 'file',
          bearerToken: widget.accessToken,
        );
      }

      final body = <String, dynamic>{
        'display_name': _nicknameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'profile_visibility': _visibility,
      };
      final birthDate = _birthDateCtrl.text.trim();
      if (birthDate.isNotEmpty) {
        body['birth_date'] = birthDate;
      }

      await widget.apiClient.patchJson(
        '/users/me',
        body: body,
        bearerToken: widget.accessToken,
      );

      await _loadProfile();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('个人资料已保存')));
      widget.onSave();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          key: const PageStorageKey<String>('profile-settings-list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
          children: [
            EditorialScreenHeader(
              title: '个人设置',
              onBack: () => Navigator.pop(context),
              trailing: EditorialPill(
                label: '资料管理',
                backgroundColor: AppColors.surfaceSoft,
                foregroundColor: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),
            _AvatarCard(
              nickname: _nicknameCtrl.text.trim().isEmpty
                  ? '未设置昵称'
                  : _nicknameCtrl.text.trim(),
              avatarPath: _avatarPath,
              avatarUrl: _remoteAvatarUrl,
              loading: _loadingProfile,
              onTap: _pickAvatar,
            ),
            const SizedBox(height: 14),
            _ProfileFieldCard(
              label: '昵称',
              controller: _nicknameCtrl,
              placeholder: '输入你的昵称',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 10),
            _ProfileFieldCard(
              label: '生日',
              controller: _birthDateCtrl,
              placeholder: 'YYYY-MM-DD',
              icon: Icons.cake_outlined,
            ),
            const SizedBox(height: 10),
            _ProfileFieldCard(
              label: '年龄',
              value: _ageLabel,
              placeholder: '-',
              icon: Icons.numbers_rounded,
              readOnly: true,
              helperText: '年龄会根据生日自动计算。',
            ),
            const SizedBox(height: 10),
            _ProfileFieldCard(
              label: '所在地',
              controller: _locationCtrl,
              placeholder: '例如：上海 徐汇',
              icon: Icons.location_on_rounded,
            ),
            const SizedBox(height: 10),
            _ProfileFieldCard(
              label: '简介',
              controller: _bioCtrl,
              placeholder: '简单介绍一下自己',
              icon: Icons.text_fields_rounded,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('资料可见范围', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _VisibilityChip(
                        label: '公开',
                        selected: _visibility == 'public',
                        onSelected: () =>
                            setState(() => _visibility = 'public'),
                      ),
                      _VisibilityChip(
                        label: '好友可见',
                        selected: _visibility == 'friends',
                        onSelected: () =>
                            setState(() => _visibility = 'friends'),
                      ),
                      _VisibilityChip(
                        label: '仅自己',
                        selected: _visibility == 'private',
                        onSelected: () =>
                            setState(() => _visibility = 'private'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '控制谁可以看到你的个人资料摘要和已发布商品。',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '头像、昵称和所在地会在商品卡片、详情页和会话中展示，请保持信息准确。',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _saveProfile,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.nickname,
    required this.avatarPath,
    required this.avatarUrl,
    required this.loading,
    required this.onTap,
  });

  final String nickname;
  final String? avatarPath;
  final String? avatarUrl;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = loading
        ? const SizedBox(
            width: 74,
            height: 74,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : avatarPath != null
        ? ClipOval(
            child: Image.file(
              File(avatarPath!),
              width: 74,
              height: 74,
              fit: BoxFit.cover,
            ),
          )
        : avatarUrl != null
        ? ClipOval(
            child: Image.network(
              avatarUrl!,
              width: 74,
              height: 74,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _AvatarFallback(name: nickname),
            ),
          )
        : _AvatarFallback(name: nickname);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              children: [
                avatar,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('头像与昵称', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '点击头像可从相册重新选择图片。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first : '我',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

class _ProfileFieldCard extends StatelessWidget {
  const _ProfileFieldCard({
    required this.label,
    this.value,
    this.controller,
    required this.placeholder,
    required this.icon,
    this.maxLines = 1,
    this.readOnly = false,
    this.helperText,
  });

  final String label;
  final String? value;
  final TextEditingController? controller;
  final String placeholder;
  final IconData icon;
  final int maxLines;
  final bool readOnly;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            initialValue: controller == null ? (value ?? '') : null,
            readOnly: readOnly,
            maxLines: maxLines,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(icon, size: 18, color: AppColors.textMuted),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              hintText: placeholder,
              fillColor: Colors.transparent,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted.withValues(alpha: 0.52),
              ),
            ),
          ),
          if (helperText != null) ...[
            const SizedBox(height: 6),
            Text(helperText!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _VisibilityChip extends StatelessWidget {
  const _VisibilityChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: selected ? AppColors.primary : AppColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
