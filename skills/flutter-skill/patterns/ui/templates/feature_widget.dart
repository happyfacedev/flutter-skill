// Feature widget — lives under lib/features/<feature>/ui/widgets/foo_card.dart.
//
// Use when a second page in the SAME feature needs this widget, or it grew
// past being a comfortable private _FooSection (own BlocBuilder slice, size).
// One page only → keep it a private _FooSection in that page file.
// Needed across features → core promotion (user decision) — see the PATTERN.md
// placement ladder.
//
// Conventions baked in:
//   - StatelessWidget, const constructor, super.key last
//   - semanticsIdentifier hoisted (the caller assigns `items-card-$index` etc.)
//   - Semantics wraps the actual interactable; Material + InkWell for ripple
//   - Tokens by semantic intent — confirm role names against the project's
//     own theme extensions

import 'package:flutter/material.dart';
import 'package:your_app/core/theme/theme.dart';

class FooCard extends StatelessWidget {
  const FooCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.semanticsIdentifier,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: semanticsIdentifier,
      button: true,
      child: Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(context.radius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.radius.card),
          child: Padding(
            padding: EdgeInsets.all(context.spacing.paddingCard),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.styles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: context.spacing.gapTight),
                      Text(
                        subtitle,
                        style: context.styles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: context.spacing.gapNormal),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
