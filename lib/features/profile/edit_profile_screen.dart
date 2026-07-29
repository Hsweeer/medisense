import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';

/// Lets the user update their profile photo and full name.
///
/// Email is intentionally read-only — it's tied to the Firebase Auth
/// account and must never be edited from here.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  File? _pickedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>().profile;
    _nameController = TextEditingController(text: profile.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _pickedImage = File(file.path));
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Could not open gallery');
    }
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Full name cannot be empty');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await context.read<ProfileProvider>().updateProfileInfo(
        name: name,
        newImageFile: _pickedImage,
      );

      if (!mounted) return;
      showToast(context, 'Profile updated');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showToast(context, 'Failed to save changes. Try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ProfileProvider>().profile;
    final email = context.read<AuthProvider>().currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Stack(
                children: [
                  _AvatarPreview(name: p.name, imageUrl: p.imageUrl, localFile: _pickedImage),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _pickImage,
                child: Text(
                  'Change photo',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _FieldLabel('Full Name'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline_rounded),
                hintText: 'Enter your full name',
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const _FieldLabel('Email'),
                const SizedBox(width: 6),
                Text('(cannot be changed)',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 6),
            IgnorePointer(
              child: TextField(
                enabled: false,
                controller: TextEditingController(
                    text: email.isEmpty ? '—' : email),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
            ),
            const SizedBox(height: 14),
            MCard(
              color: AppColors.primary.withValues(alpha: .06),
              border: Border.all(color: AppColors.primary.withValues(alpha: .25)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your email is used for account security and cannot be changed.',
                      style: TextStyle(
                          fontSize: 12.5, height: 1.4, color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: _isSaving ? 'Saving…' : 'Save Changes',
              onPressed: _isSaving ? null : _handleSave,
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                child: Text('Cancel',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
  }
}

/// Shows, in priority order: a freshly picked local image, the existing
/// remote profile image, or a fallback initials avatar.
class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.name,
    required this.imageUrl,
    required this.localFile,
  });

  final String name;
  final String? imageUrl;
  final File? localFile;

  static const _size = 108.0;

  @override
  Widget build(BuildContext context) {
    if (localFile != null) {
      return CircleAvatar(radius: _size / 2, backgroundImage: FileImage(localFile!));
    }
    return InitialsAvatar(name, size: _size, imageUrl: imageUrl);
  }
}