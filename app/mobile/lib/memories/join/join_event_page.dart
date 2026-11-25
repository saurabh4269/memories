import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/memories/join/director_client.dart';
import 'package:immich_mobile/memories/join/join_link.dart';
import 'package:immich_mobile/memories/join/join_service.dart';
import 'package:immich_mobile/memories/join/languages.dart';
import 'package:immich_mobile/memories/join/memories_ui.dart';
import 'package:immich_mobile/memories/join/qr_scan_page.dart';
import 'package:immich_mobile/routing/router.dart';

/// "Join your family's event" screen.
///
/// 1. Scan the host's QR (or type the code), 2. tell us who you are,
/// 3. we redeem the invite, sign in to the family server and open the album.
class JoinEventPage extends ConsumerStatefulWidget {
  /// Pre-filled invite, e.g. from a `memories://join` deep link.
  final JoinLink? initialLink;

  const JoinEventPage({super.key, this.initialLink});

  /// Opens the page on the root navigator (works without a registered route).
  static Future<void> open(BuildContext context, {JoinLink? link}) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => JoinEventPage(initialLink: link)));

  @override
  ConsumerState<JoinEventPage> createState() => _JoinEventPageState();
}

class _JoinEventPageState extends ConsumerState<JoinEventPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  JoinLink? _link;
  String? _language;
  MemberRole _role = MemberRole.adult;
  JoinStep? _step;
  String? _error;

  bool get _busy => _step != null && _step != JoinStep.done;

  @override
  void initState() {
    super.initState();
    _link = widget.initialLink;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _language ??= languageByCode(Localizations.maybeLocaleOf(context)?.languageCode)?.code ?? 'hi';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final link = await QrScanPage.open(context);
    if (link != null && mounted) {
      setState(() {
        _link = link;
        _error = null;
      });
    }
  }

  void _useTypedCode() {
    final link = JoinLink.tryParse(_codeController.text);
    setState(() {
      _link = link;
      _error = link == null ? 'That code doesn\'t look right. Please check it and try again.' : null;
    });
  }

  Future<void> _join() async {
    final link = _link;
    final name = _nameController.text.trim();
    if (link == null) {
      return;
    }
    if (name.isEmpty) {
      setState(() => _error = 'Please write your name.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final router = ref.read(appRouterProvider);
    try {
      final outcome = await ref
          .read(joinServiceProvider)
          .join(
            link: link,
            name: name,
            language: _language ?? 'en',
            role: _role,
            onStep: (step) {
              if (mounted) {
                setState(() => _step = step);
              }
            },
          );
      await router.replaceAll([const TabShellRoute()]);
      final album = outcome.album;
      if (album != null) {
        unawaited(router.push(RemoteAlbumRoute(album: album)));
      }
    } on DirectorException catch (e) {
      if (mounted) {
        setState(() {
          _step = null;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = null;
          _error = 'Something went wrong. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Preview elder sizing as soon as "Elder" is picked.
    final scale = _role == MemberRole.elder ? 1.25 : 1.0;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(media.textScaler.scale(1) * scale)),
      child: Scaffold(
        appBar: AppBar(title: const Text('Join the event'), centerTitle: true),
        body: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: _link == null ? _buildCodeStep(context) : _buildProfileStep(context),
              ),
              if (_busy) _ProgressOverlay(message: _step!.message),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCodeStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 16),
      Icon(Icons.qr_code_scanner_rounded, size: 96, color: theme.colorScheme.primary),
      const SizedBox(height: 16),
      Text(
        'Join your family\'s event',
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        'Ask the host to show the QR code, then scan it with your camera.',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 32),
      MemoriesBigButton(label: 'Scan the QR', icon: Icons.photo_camera_rounded, onPressed: _scan),
      const SizedBox(height: 32),
      Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('or type the code', style: theme.textTheme.titleMedium),
          ),
          const Expanded(child: Divider()),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _codeController,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.w600),
        decoration: _fieldDecoration(context, hint: 'ABC123'),
        onSubmitted: (_) => _useTypedCode(),
      ),
      const SizedBox(height: 12),
      MemoriesBigButton(label: 'Continue', secondary: true, onPressed: _useTypedCode),
      if (_error != null) _ErrorText(_error!),
    ];
  }

  List<Widget> _buildProfileStep(BuildContext context) {
    final theme = Theme.of(context);
    return [
      _InviteFoundBanner(code: _link!.code, onChange: _busy ? null : () => setState(() => _link = null)),
      const MemoriesSectionTitle('Your name'),
      TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 22),
        decoration: _fieldDecoration(context, hint: 'e.g. Dadi, Ravi, Meena'),
        textInputAction: TextInputAction.done,
      ),
      const MemoriesSectionTitle('Language'),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final lang in kMemoriesLanguages)
            ChoiceChip(
              label: Text(lang.nativeName, style: const TextStyle(fontSize: 20)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              selected: _language == lang.code,
              showCheckmark: false,
              tooltip: lang.englishName,
              onSelected: (_) => setState(() => _language = lang.code),
            ),
        ],
      ),
      const MemoriesSectionTitle('I am'),
      Row(
        children: [
          for (final role in MemberRole.values) ...[
            if (role != MemberRole.values.first) const SizedBox(width: 10),
            Expanded(
              child: _RoleTile(role: role, selected: _role == role, onTap: () => setState(() => _role = role)),
            ),
          ],
        ],
      ),
      if (_role == MemberRole.elder)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'We\'ll use bigger text and spoken prompts for you.',
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
      if (_error != null) _ErrorText(_error!),
      const SizedBox(height: 28),
      MemoriesBigButton(label: 'Join', icon: Icons.celebration_rounded, busy: _busy, onPressed: _join),
    ];
  }

  InputDecoration _fieldDecoration(BuildContext context, {required String hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  );
}

class _InviteFoundBanner extends StatelessWidget {
  final String code;
  final VoidCallback? onChange;

  const _InviteFoundBanner({required this.code, this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: scheme.onPrimaryContainer, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Invite found ($code)',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
              ),
            ),
            if (onChange != null)
              TextButton(
                onPressed: onChange,
                child: const Text('Change', style: TextStyle(fontSize: 18)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final MemberRole role;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({required this.role, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: role.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
          ),
          child: Column(
            children: [
              Text(role.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 6),
              Text(role.label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String text;

  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.error, fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

class _ProgressOverlay extends StatelessWidget {
  final String message;

  const _ProgressOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 5)),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}
