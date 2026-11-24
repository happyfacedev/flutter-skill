// Feature widget — lives under lib/features/<feature>/ui/widgets/foo_card.dart.
//
// Use when:
//   • Two or more pages in the SAME feature need this widget
//   • The widget grew large enough that keeping it in the page file is a distraction
//   • The widget owns its own BlocBuilder consuming a slice of state
//
// Do NOT use this template when:
//   • The widget is used in exactly one page → leave it as private _FooSection in that page file
//   • The widget is needed across features → promote to core/widgets/ (regular themed) or core/design/ (Ds*)
//
// Conventions baked in below:
//   - StatelessWidget, const constructor, super.key last
//   - semanticsIdentifier hoisted as a parameter (the caller assigns the
//     feature-specific identifier — `items-card-$index`, etc.)
//   - context.colors / context.styles / AppSize tokens throughout
//   - Material + InkWell for ripple feedback on a tappable card
//   - Identifier passed through unconditionally (null = not under test, which is fine)

import 'package:flutter/material.dart';
import 'package:core_boilerplate/core/theme/theme.dart';

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
        borderRadius: BorderRadius.circular(AppSize.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSize.radius),
          child: Padding(
            padding: const EdgeInsets.all(AppSize.s16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.styles.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSize.s4),
                      Text(
                        subtitle,
                        style: context.styles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSize.s12),
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
