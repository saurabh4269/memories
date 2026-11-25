import 'package:flutter/material.dart';

/// Small set of large, high-contrast building blocks shared by the Memories
/// screens (join, invite, post). Designed for elders: big targets, big text.
class MemoriesBigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool busy;

  const MemoriesBigButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.secondary = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 28), const SizedBox(width: 12)],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
    const size = Size.fromHeight(64);
    return secondary
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size, shape: shape, side: const BorderSide(width: 2)),
            onPressed: busy ? null : onPressed,
            child: child,
          )
        : FilledButton(
            style: FilledButton.styleFrom(minimumSize: size, shape: shape),
            onPressed: busy ? null : onPressed,
            child: child,
          );
  }
}

class MemoriesSectionTitle extends StatelessWidget {
  final String text;

  const MemoriesSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

/// A sheet "grabber" + title row, Apple style.
class MemoriesSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const MemoriesSheetHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}

void showMemoriesSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 18)),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
