// Reusable-widget use case — one variant per visual state, fixed values only.
// Replace your_app / PrimaryButton. Lives at:
//   lib/widgetbook/use_cases/core/widgets/primary_button_use_cases.dart
//
// Constructor-injected widgets need no fakes: pass values directly. NO
// context.knobs.* — the design catalog renders stories without the
// Widgetbook knob runtime, so a knob call throws a red error tile. Every
// state that matters (loading, disabled, error) is its own fixed variant
// (each is a separately reviewable tile in light AND dark).

import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;
import 'package:your_app/core/widgets/ghost_button.dart';
import 'package:your_app/core/widgets/primary_button.dart';
import 'package:your_app/core/widgets/secondary_button.dart';

@widgetbook.UseCase(name: 'Default', type: PrimaryButton)
Widget primaryButtonDefault(BuildContext context) => Center(
      child: PrimaryButton(
        label: 'Continue',
        onPressed: () {},
      ),
    );

@widgetbook.UseCase(name: 'Loading', type: PrimaryButton)
Widget primaryButtonLoading(BuildContext context) => const Center(
      child: PrimaryButton(label: 'Continue', isLoading: true, onPressed: null),
    );

@widgetbook.UseCase(name: 'Disabled', type: PrimaryButton)
Widget primaryButtonDisabled(BuildContext context) => const Center(
      child: PrimaryButton(label: 'Continue', onPressed: null),
    );

// ── Synthetic gallery showcase ─────────────────────────────────────────────
// For token/inventory galleries (typography, colors, the full button family),
// declare the showcase class IN THIS FILE: its `type:` then files the tile
// under widgetbook/use_cases/ instead of a feature path (Rule 2).

class ButtonsShowcase extends StatelessWidget {
  const ButtonsShowcase({super.key});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PrimaryButton(label: 'Primary', onPressed: () {}),
          SecondaryButton(label: 'Secondary', onPressed: () {}),
          GhostButton(label: 'Ghost', onPressed: () {}),
          const PrimaryButton(label: 'Disabled', onPressed: null),
          const PrimaryButton(label: 'Loading', isLoading: true, onPressed: null),
        ],
      );
}

@widgetbook.UseCase(name: 'gallery', type: ButtonsShowcase)
Widget buttonsShowcase(BuildContext context) => const ButtonsShowcase();
