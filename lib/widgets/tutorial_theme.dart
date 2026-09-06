import 'package:flutter/material.dart';

class TutorialThemeTokens {
  static const Color overlay = Color(0xAA020617);
  static const Color panelStart = Color(0xFF1E293B);
  static const Color panelEnd = Color(0xFF0F172A);
  static const Color border = Color(0xFF93C5FD);
  static const Color title = Color(0xFFE2E8F0);
  static const Color body = Color(0xFFCBD5E1);
  static const Color button = Color(0xFF2563EB);

  static const TextStyle titleStyle = TextStyle(
    color: title,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: body,
    fontSize: 12,
    height: 1.35,
    decoration: TextDecoration.none,
  );

  static const TextStyle buttonStyle = TextStyle(
    color: title,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.none,
  );
}

class TutorialPanel extends StatelessWidget {
  const TutorialPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TutorialThemeTokens.panelStart,
            TutorialThemeTokens.panelEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: TutorialThemeTokens.border.withValues(alpha: 0.32),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class TutorialDots extends StatelessWidget {
  const TutorialDots({
    super.key,
    required this.count,
    required this.currentIndex,
  });

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 16 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? TutorialThemeTokens.title : Colors.white54,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
