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
  bool _saving = false;

  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _birthDateCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _bioCtrl;

  String _readField(String key) =>
      widget.session.profile?[key]?.toString() ??
      widget.session.user[key]?.toString() ??
      '';

  String get _ageLabel {
    final age = (widget.session.profile?['age_years'] as num?)?.toInt();
    if (age != null) return '$age';
    final bd = _birthDateCtrl.text.trim();
    if (bd.isEmpty) return '-';
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
    if (_visibility.isEmpty) _visibility = 'public';
    _nicknameCtrl = TextEditingController(text: _readField('display_name'));
    _birthDateCtrl = TextEditingController(text: _readField('birth_date'));
    _locationCtrl = TextEditingController(text: _readField('location'));
    _bioCtrl = TextEditingController(text: _readField('bio'));
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _birthDateCtrl.dispose();
    _locationCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
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
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 1. Upload avatar if changed.
      if (_avatarPath != null) {
        await widget.apiClient.uploadFile(
          '/users/me/avatar',
          filePath: _avatarPath!,
          fieldName: 'file',
          bearerToken: widget.accessToken,
        );
      }

      // 2. PATCH profile fields.
      final body = <String, dynamic>{
        'display_name': _nicknameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'profile_visibility': _visibility,
      };
      final bd = _birthDateCtrl.text.trim();
      if (bd.isNotEmpty) body['birth_date'] = bd;

      await widget.apiClient.patchJson(
        '/users/me',
        body: body,
        bearerToken: widget.accessToken,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
        widget.onSave();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
            // --- Header ---
            EditorialScreenHeader(
              title: 'Profile settings',
              onBack: () => Navigator.pop(context),
              trailing: EditorialPill(
                label: 'Personal info',
                backgroundColor: AppColors.surfaceSoft,
                foregroundColor: AppColors.text,
              ),
            ),
            const SizedBox(height: 16),

            // --- Avatar card ---
            _AvatarCard(
              nickname: _nicknameCtrl.text,
              avatarPath: _avatarPath,
              onTap: _pickAvatar,
            ),
            const SizedBox(height: 16),

            // --- Field cards ---
            _ProfileFieldCard(
              label: 'Nickname',
              controller: _nicknameCtrl,
              placeholder: 'Enter your nickname',
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _ProfileFieldCard(
              label: 'Birth date',
              controller: _birthDateCtrl,
              placeholder: 'YYYY-MM-DD',
              icon: Icons.cake_outlined,
            ),
            const SizedBox(height: 12),
            _ProfileFieldCard(
              label: 'Age',
              value: _ageLabel,
              placeholder: '-',
              icon: Icons.numbers_rounded,
              readOnly: true,
              helperText: 'Age is derived from the birth date.',
            ),
            const SizedBox(height: 12),
            _ProfileFieldCard(
              label: 'Location',
              controller: _locationCtrl,
              placeholder: 'City, Region',
              icon: Icons.location_on_rounded,
            ),
            const SizedBox(height: 12),
            _ProfileFieldCard(
              label: 'Bio',
              controller: _bioCtrl,
              placeholder: 'Tell us about yourself...',
              icon: Icons.text_fields_rounded,
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            // --- Visibility selector ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROFILE VISIBILITY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.1,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _VisibilityChip(
                        label: 'Public',
                        selected: _visibility == 'public',
                        onSelected: () =>
                            setState(() => _visibility = 'public'),
                      ),
                      _VisibilityChip(
                        label: 'Friends',
                        selected: _visibility == 'friends',
                        onSelected: () =>
                            setState(() => _visibility = 'friends'),
                      ),
                      _VisibilityChip(
                        label: 'Private',
                        selected: _visibility == 'private',
                        onSelected: () =>
                            setState(() => _visibility = 'private'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Controls who can see your profile summary and listings.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- Info banner ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your profile data is stored securely and only visible to users based on your visibility setting.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- Save button ---
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
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Avatar card — tap to pick photo ─────────────────────────

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.nickname,
    required this.avatarPath,
    required this.onTap,
  });

  final String nickname;
  final String? avatarPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
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
          // Tappable avatar circle.
          GestureDetector(
            onTap: onTap,
            child: Stack(
              children: [
                if (avatarPath != null)
                  ClipOval(
                    child: Image.file(
                      File(avatarPath!),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: EditorialImagePlaceholder(
                      label: nickname.isNotEmpty ? nickname : 'Avatar',
                      subtitle: '',
                      badge: 'Profile',
                      height: 80,
                      circular: true,
                      borderRadius: 999,
                      accentColor: AppColors.accent,
                    ),
                  ),
                // Camera overlay badge.
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
          const SizedBox(width: 16),
          // Title and description.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Avatar & nickname',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap the avatar to change your photo.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Field card ──────────────────────────────────────────────

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
          TextFormField(
            controller: controller,
            initialValue: controller == null ? (value ?? '') : null,
            readOnly: readOnly,
            maxLines: maxLines,
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(icon, size: 18, color: AppColors.textMuted),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              hintText: placeholder,
              fillColor: Colors.transparent,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 2),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted.withValues(alpha: 0.52),
                  ),
            ),
          ),
          if (helperText != null) ...[
            const SizedBox(height: 8),
            Text(helperText!,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ─── Visibility chip ─────────────────────────────────────────

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