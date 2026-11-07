import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models.dart';

class AttachmentSheet extends StatefulWidget {
  const AttachmentSheet({
    super.key,
    required this.onAttach,
    required this.onPickFiles,
    this.warnUnsupported = false,
  });

  final ValueChanged<ChatAttachment> onAttach;
  final Future<void> Function() onPickFiles;
  final bool warnUnsupported;

  @override
  State<AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<AttachmentSheet> {
  static const int _maxBytes = 20 * 1024 * 1024;
  static const int _recentCount = 10;

  final ImagePicker _picker = ImagePicker();
  List<AssetEntity>? _recent;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final PermissionState permission;
    try {
      permission = await PhotoManager.requestPermissionExtend();
    } catch (_) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    if (!permission.hasAccess) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    try {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _recent = <AssetEntity>[]);
        return;
      }
      final assets = await paths.first.getAssetListPaged(
        page: 0,
        size: _recentCount,
      );
      if (mounted) setState(() => _recent = assets);
    } catch (_) {
      if (mounted) setState(() => _recent = <AssetEntity>[]);
    }
  }

  void _deliver(String name, String mime, Uint8List bytes) {
    final l10n = AppLocalizations.of(context);
    if (bytes.lengthInBytes > _maxBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.attachmentTooBig)),
      );
      Navigator.of(context).pop();
      return;
    }
    widget.onAttach(
      ChatAttachment.fromBytes(mimeType: mime, name: name, bytes: bytes),
    );
    Navigator.of(context).pop();
  }

  String _mimeFor(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickAsset(AssetEntity asset) async {
    try {
      final bytes = await asset.originBytes;
      if (bytes == null || !mounted) return;
      _deliver(
        asset.title ?? 'photo.jpg',
        asset.mimeType ?? 'image/jpeg',
        bytes,
      );
    } catch (_) {}
  }

  Future<void> _shoot() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2560,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      _deliver(picked.name, _mimeFor(picked.name), bytes);
    } catch (_) {}
  }

  Future<void> _pickAlbum() async {
    try {
      final picked = await _picker.pickMultiImage(maxWidth: 2560);
      if (picked.isEmpty) return;
      final attachments = <ChatAttachment>[];
      for (final file in picked) {
        final bytes = await file.readAsBytes();
        if (bytes.lengthInBytes > _maxBytes) continue;
        attachments.add(
          ChatAttachment.fromBytes(
            mimeType: _mimeFor(file.name),
            name: file.name,
            bytes: bytes,
          ),
        );
      }
      if (!mounted || attachments.isEmpty) return;
      for (final attachment in attachments) {
        widget.onAttach(attachment);
      }
      Navigator.of(context).pop();
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    Navigator.of(context).pop();
    await widget.onPickFiles();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final recent = _recent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.attach,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (widget.warnUnsupported) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.imagesMaybeUnsupported,
                      style: Theme.of(context).textTheme.bodySmall?.apply(
                            color: scheme.tertiary,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (_denied)
              Row(
                children: <Widget>[
                  Icon(Icons.photo_library_outlined, color: scheme.outline),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l10n.grantPhotoAccess)),
                  TextButton(
                    onPressed: PhotoManager.openSetting,
                    child: Text(l10n.openSettings),
                  ),
                ],
              )
            else
              SizedBox(
                height: 112,
                child: recent == null
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : recent.isEmpty
                        ? Center(
                            child: Text(
                              '—',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                          )
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recent.length,
                            separatorBuilder: (BuildContext ctx, int i) =>
                                const SizedBox(width: 8),
                            itemBuilder: (BuildContext ctx, int i) {
                              final asset = recent[i];
                              return GestureDetector(
                                onTap: () => _pickAsset(asset),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 112,
                                    height: 112,
                                    child: FutureBuilder<Uint8List?>(
                                      future: asset.thumbnailDataWithSize(
                                        const ThumbnailSize(224, 224),
                                      ),
                                      builder: (BuildContext ctx,
                                          AsyncSnapshot<Uint8List?> snapshot) {
                                        final data = snapshot.data;
                                        if (data == null) {
                                          return ColoredBox(
                                            color: scheme
                                                .surfaceContainerHighest,
                                          );
                                        }
                                        return Image.memory(
                                          data,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_camera_outlined,
                    label: l10n.attachCamera,
                    onTap: _shoot,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SourceButton(
                    icon: Icons.photo_library_outlined,
                    label: l10n.attachAlbum,
                    onTap: _pickAlbum,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SourceButton(
                    icon: Icons.attach_file,
                    label: l10n.attachFile,
                    onTap: _pickFiles,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 68,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: scheme.onSurface),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.apply(color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
