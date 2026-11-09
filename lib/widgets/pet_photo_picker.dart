import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import 'common.dart';

/// Gallery/camera picker that uploads through Petsy API and exposes the media URL.
class PetPhotoPicker extends StatefulWidget {
  const PetPhotoPicker({
    super.key,
    required this.imageUrl,
    required this.onChanged,
    this.enabled = true,
    this.title,
    this.hint,
    this.emptyIcon = Icons.add_a_photo_outlined,
  });

  final String? imageUrl;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  /// Empty-state title; defaults to pet photo copy.
  final String? title;
  /// Empty-state hint under the title.
  final String? hint;
  final IconData emptyIcon;

  @override
  State<PetPhotoPicker> createState() => _PetPhotoPickerState();
}

class _PetPhotoPickerState extends State<PetPhotoPicker> {
  final _picker = ImagePicker();
  String? _localPath;
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    if (!widget.enabled || _uploading) return;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;

      setState(() {
        _localPath = file.path;
        _uploading = true;
      });

      final url = await context.api.uploadImage(file.path);
      if (!mounted) return;
      widget.onChanged(url);
      context.snack(context.t('photo_uploaded'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _localPath = null);
      context.snack(context.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _clear() {
    setState(() => _localPath = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.imageUrl?.trim();
    final hasPhoto = (_localPath != null && _localPath!.isNotEmpty) ||
        (remote != null && remote.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(PetsyRadius.lg),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_localPath != null)
                  Image.file(File(_localPath!), fit: BoxFit.cover)
                else if (remote != null && remote.isNotEmpty)
                  NetImage(remote)
                else
                  ColoredBox(
                    color: PetsyColors.primarySoft,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.emptyIcon, size: 36, color: PetsyColors.primaryDark),
                          const SizedBox(height: 8),
                          Text(
                            widget.title ?? context.t('pet_photo'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.hint ?? context.t('pet_photo_pick_hint'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: PetsyColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_uploading)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.enabled && !_uploading ? () => _pick(ImageSource.gallery) : null,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(context.t('choose_gallery')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.enabled && !_uploading ? () => _pick(ImageSource.camera) : null,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(context.t('take_photo')),
              ),
            ),
          ],
        ),
        if (hasPhoto) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.enabled && !_uploading ? _clear : null,
            child: Text(context.t('remove_photo')),
          ),
        ],
      ],
    );
  }
}
