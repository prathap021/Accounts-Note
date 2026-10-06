import 'package:flutter/material.dart';

import '../core/services/avatar_cache.dart';
import '../core/utils/avatar_provider.dart';

/// The user's profile photo, with their initials underneath it at all times.
///
/// The initials are not a fallback branch — they are painted first and the
/// photo is laid over them. So whatever goes wrong with the image (no network,
/// an expired provider URL, bytes that won't decode) the circle still shows
/// who is signed in instead of going blank. Remote photos are read through
/// [AvatarCache], which keeps them on disk, so a cold start with no network
/// still paints the real photo.
class UserAvatar extends StatefulWidget {
  final String? photoUrl;
  final String? name;
  final String? email;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TextStyle? textStyle;

  /// Injected in tests so they never touch the disk or the network.
  final AvatarCache? cache;

  const UserAvatar({
    super.key,
    required this.radius,
    this.photoUrl,
    this.name,
    this.email,
    this.backgroundColor,
    this.foregroundColor,
    this.textStyle,
    this.cache,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  ImageProvider? _image;

  AvatarCache get _cache => widget.cache ?? AvatarCache.instance;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      setState(_resolve);
    }
  }

  void _resolve() {
    final url = widget.photoUrl?.trim();
    _image = dataUriImage(url);
    if (_image != null || !isRemoteAvatar(url)) return;

    // Already in memory: paint it on this frame rather than flashing initials.
    final cached = _cache.peek(url!);
    if (cached != null) {
      _image = MemoryImage(cached);
      return;
    }

    _cache.load(url).then((bytes) {
      if (!mounted || bytes == null) return;
      // The photo may have changed while we were off reading it.
      if (widget.photoUrl?.trim() != url) return;
      setState(() => _image = MemoryImage(bytes));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = widget.backgroundColor ?? scheme.primary;
    final foreground = widget.foregroundColor ?? scheme.onPrimary;
    final initials = initialsFor(widget.name, email: widget.email);

    final base = widget.textStyle ??
        TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: widget.radius * 0.72,
        );
    final style = base.color == null ? base.copyWith(color: foreground) : base;

    final diameter = widget.radius * 2;
    return SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: background,
              child: Center(
                child: Text(
                  initials,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: style,
                ),
              ),
            ),
            if (_image != null)
              Image(
                image: _image!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                // Anything unreadable falls through to the initials below.
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}
