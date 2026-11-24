import 'package:material_ui/material_ui.dart';

class MosquePalette {
  static const emerald = Color(0xFF1E7662);
  static const mint = Color(0xFFEAF6F0);
  static const ocean = Color(0xFF285F93);
  static const sky = Color(0xFFEAF3FC);
  static const plum = Color(0xFF71528D);
  static const lavender = Color(0xFFF0EBF8);
  static const amber = Color(0xFFC28B38);
}

class MosqueSectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  const MosqueSectionHeader({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: dark ? .22 : .09),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 32)),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class MosqueCardShell extends StatelessWidget {
  final Color accent;
  final Widget child;
  const MosqueCardShell({super.key, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF252B27) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark ? const Color(0xFF404A42) : accent.withValues(alpha: .18),
        ),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: child,
    );
  }
}

class MosqueTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  const MosqueTag({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class MosqueMetaLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accent;
  const MosqueMetaLine({
    super.key,
    required this.icon,
    required this.text,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
