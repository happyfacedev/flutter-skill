// Core reusable widget — lives under lib/core/widgets/<name>.dart.
//
// Use when:
//   • Two or more features need this widget on authenticated themed surfaces
//   • Color/style adapts to light/dark mode via context.colors / context.styles
//
// For auth / onboarding / intro surfaces (theme-independent, dark gradient),
// use lib/core/design/ds_<name>.dart with the Ds* prefix instead — that family
// uses AppColors.brand* statics deliberately.
//
// This template demonstrates the StatelessWidget outer + _FooBody inner split
// for when an inner stateful piece is needed. If your widget has no state, the
// outer class is the whole widget — drop the inner split.

import 'package:flutter/material.dart';
import 'package:core_boilerplate/core/theme/theme.dart';

/// A toggleable info chip with press feedback.
///
/// Outer is StatelessWidget so Semantics + the public API live at the top.
/// Inner _InfoChipBody is StatefulWidget because it owns a press animation
/// — the pattern matches MainButton / _MainButtonBody in this folder.
class InfoChip extends StatelessWidget {
  const InfoChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.semanticsIdentifier,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticsIdentifier,
      button: true,
      child: _InfoChipBody(
        label: label,
        icon: icon,
        onTap: onTap,
      ),
    );
  }
}

class _InfoChipBody extends StatefulWidget {
  const _InfoChipBody({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  State<_InfoChipBody> createState() => _InfoChipBodyState();
}

class _InfoChipBodyState extends State<_InfoChipBody> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSize.s12,
          vertical: AppSize.s8,
        ),
        decoration: BoxDecoration(
          color: _isPressed
              ? context.colors.primaryPressed
              : context.colors.primary,
          borderRadius: BorderRadius.circular(AppSize.roundedRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: AppSize.iconSmall,
                color: context.colors.buttonText,
              ),
              const SizedBox(width: AppSize.s6),
            ],
            Text(
              widget.label,
              style: context.styles.statusBadge.copyWith(
                color: context.colors.buttonText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
