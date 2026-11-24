// List page — collection view with pull-to-refresh, status switching, tap-to-detail.
//
// Lives at:
//   lib/features/<feature>/ui/pages/<feature>_page.dart
//
// Pairs with:
//   /cubit-creation         (the FeatureCubit + FeatureState)
//   /widget-creation        (extracting _FeatureCard out of this file)
//   /navigation-gorouter    (wiring this page into AppRoutes)
//   /failure-modeling       (the Failure used in state.error)
//   /localization-arb       (the context.localization.feature* keys)
//
// Conventions illustrated:
//   - Outer StatelessWidget provides the cubit via BlocProvider(create:).
//   - Inner _FeatureView consumes; Scaffold + SafeArea is the envelope.
//   - Each BlocBuilder has a buildWhen narrowed to the slice it consumes.
//   - Status switch with the "keep list visible on refresh" guard pattern.
//   - Semantics(identifier:) wraps the actual interactable, not its container.
//   - List items include `$index` in their identifier so Maestro can target rows.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:your_app/core/injection/injection.dart';
import 'package:your_app/core/localization/localization_extension.dart';
import 'package:your_app/core/router/routes.dart';
import 'package:your_app/core/theme/theme.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';

class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FeatureCubit>()..loadItems(),
      child: const _FeatureView(),
    );
  }
}

class _FeatureView extends StatelessWidget {
  const _FeatureView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            _FeatureHeader(),
            SizedBox(height: AppSize.s12),
            Expanded(child: _FeatureList()),
          ],
        ),
      ),
    );
  }
}

class _FeatureHeader extends StatelessWidget {
  const _FeatureHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.s20,
        AppSize.s16,
        AppSize.s20,
        0,
      ),
      child: Text(
        context.localization.featureTitle,
        style: context.styles.pageTitle,
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeatureCubit, FeatureState>(
      buildWhen: (prev, curr) =>
          prev.status != curr.status || prev.items != curr.items,
      builder: (context, state) {
        return switch (state.status) {
          // First load: show a spinner. Subsequent loads keep the list visible
          // (the `when state.items.isEmpty` guard distinguishes the two).
          BlocStatus.initial || BlocStatus.loading when state.items.isEmpty =>
            Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
          BlocStatus.failure when state.items.isEmpty => _ErrorContent(
              onRetry: () => context.read<FeatureCubit>().refresh(),
            ),
          _ => _SuccessList(
              items: state.items,
              onRefresh: () async =>
                  context.read<FeatureCubit>().refresh(),
            ),
        };
      },
    );
  }
}

class _SuccessList extends StatelessWidget {
  const _SuccessList({required this.items, required this.onRefresh});

  final List<FeatureItem> items;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        color: context.colors.primary,
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            Center(
              child: Text(
                context.localization.featureEmpty,
                style: context.styles.subtitle,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSize.s20,
          0,
          AppSize.s20,
          AppSize.s16,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => Container(
          height: 1,
          color: context.colors.divider,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return Semantics(
            identifier: 'feature-card-$index',
            button: true,
            child: InkWell(
              onTap: () => context.pushNamed(
                AppRoutes.featureDetail.name,
                pathParameters: {'id': item.id},
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSize.s12),
                child: Text(item.title, style: context.styles.subtitle),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.localization;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSize.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: AppSize.s40,
              color: context.colors.hint,
            ),
            const SizedBox(height: AppSize.s12),
            Text(
              l.featureLoadFailed,
              textAlign: TextAlign.center,
              style: context.styles.subtitle,
            ),
            const SizedBox(height: AppSize.s16),
            Semantics(
              identifier: 'feature-retry',
              button: true,
              child: FilledButton(
                onPressed: onRetry,
                child: Text(l.featureRetry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
