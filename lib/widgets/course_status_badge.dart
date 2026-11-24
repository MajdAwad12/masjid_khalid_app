import 'package:material_ui/material_ui.dart';

/// Shared accessible badges for courses and enrollment decisions.
class CourseStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const CourseStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  static Color accepted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF75E1A5)
      : const Color(0xFF167D49);

  static Color rejected(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF9797)
      : const Color(0xFFBC323D);

  static Color full(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF80BBFF)
      : const Color(0xFF1766C3);

  static Color pending(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
