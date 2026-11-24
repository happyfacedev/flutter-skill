// Core reusable widget — lives under lib/core/widgets/<name>.dart.
//
// Only lands here with real reuse: two or more features need it, and the
// promotion was approved by the user. Plain names (PrimaryButton, PillInput —
// no prefixes); when a name collides with a Flutter/Material class, pick a
// descriptive alternative (SelectableChip), never a prefix.
//
// Demonstrates the stateless-outer / stateful-body split for when a widget
// owns UI-only state (press feedback here). No state → the outer class is
// the whole widget; drop the inner split.
//
// Tokens by semantic intent — confirm role names against the project's own
// theme extensions.

import 'package:flutter/material.dart';
import 'package:your_app/core/theme/theme.dart';

/// A toggleable info chip with press feedback.
///
/// Outer is StatelessWidget so Semantics + the public API live at the top;
/// inner _InfoChipBody owns the press state.
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
        duration: context.motion.snap,
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.gapNormal,
          vertical: context.spacing.gapCompact,
        ),
        decoration: BoxDecoration(
          color: _isPressed
              ? context.colors.primaryPressed
              : context.colors.primary,
          borderRadius: BorderRadius.circular(context.radius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: context.iconSize.sm,
                color: context.colors.buttonText,
              ),
              SizedBox(width: context.spacing.gapTight),
            ],
            Text(
              widget.label,
              style: context.styles.labelMedium.copyWith(
                color: context.colors.buttonText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
