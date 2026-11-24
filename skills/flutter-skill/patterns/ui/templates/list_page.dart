// List page — collection view with pull-to-refresh, status switching, tap-to-detail.
//
// Lives at: lib/features/<feature>/ui/pages/<feature>_page.dart
//
// Conventions illustrated:
//   - Outer StatelessWidget provides the cubit; inner _FeatureView consumes.
//   - Scaffold + SafeArea envelope; sections own their own padding.
//   - Each BlocBuilder has buildWhen narrowed to the slice it consumes.
//   - Status switch with the "keep list visible on refresh" guard.
//   - Semantics(identifier:) wraps the actual interactable; list items carry $index.
//   - Tokens by semantic intent (spacing.pagePadding, radius.card, iconSize.xl) —
//     confirm role names against the project's own theme extensions.

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
          children: [
            const _FeatureHeader(),
            SizedBox(height: context.spacing.gapNormal),
            const Expanded(child: _FeatureList()),
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
      padding: EdgeInsets.fromLTRB(
        context.spacing.pagePadding,
        context.spacing.gapCozy,
        context.spacing.pagePadding,
        0,
      ),
      child: Text(
        context.localization.featureTitle,
        style: context.styles.titleLarge,
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
          prev.status != curr.status ||
          prev.items != curr.items ||
          prev.error != curr.error,
      builder: (context, state) {
        return switch (state.status) {
          // First load: spinner. Subsequent loads keep the list visible —
          // the `when state.items.isEmpty` guard distinguishes the two.
          BlocStatus.initial || BlocStatus.loading when state.items.isEmpty =>
            Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
          BlocStatus.failure when state.items.isEmpty => _ErrorContent(
              failure: state.error,
              onRetry: () => context.read<FeatureCubit>().refresh(),
            ),
          _ => _SuccessList(
              items: state.items,
              onRefresh: () async => context.read<FeatureCubit>().refresh(),
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
            // EmptyState = the design-tier placeholder (lib/core/widgets/).
            EmptyState(title: context.localization.featureEmpty),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: context.colors.primary,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          context.spacing.pagePadding,
          0,
          context.spacing.pagePadding,
          context.spacing.gapCozy,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => Container(
          height: context.spacing.hairline,
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
                padding:
                    EdgeInsets.symmetric(vertical: context.spacing.gapNormal),
                child: Text(item.title, style: context.styles.titleMedium),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  const _ErrorContent({required this.failure, required this.onRetry});

  final Failure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // ErrorState = the design-tier error pane (lib/core/widgets/); the
    // Failure carries its own localized copy — /failure-modeling.
    return ErrorState(
      message: failure?.getTitle(context) ??
          context.localization.featureLoadFailed,
      retrySemanticsIdentifier: 'feature-retry',
      onRetry: onRetry,
    );
  }
}
