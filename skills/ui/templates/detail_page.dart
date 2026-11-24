// Detail page — single entity with sub-sections, action bar, and side effects.
//
// Lives at: lib/features/<feature>/ui/pages/<feature>_detail_page.dart
//
// Conventions illustrated:
//   - MultiBlocProvider supplies multiple cubits (detail + action).
//   - MultiBlocListener handles side effects (snackbar, refresh-after-action)
//     with listenWhen narrowed per listener.
//   - BlocBuilder at the section level — never the whole page — with buildWhen.
//   - context.read<Cubit>() only in callbacks.
//   - Tokens by semantic intent — confirm role names against the project's
//     own theme extensions.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:your_app/core/injection/injection.dart';
import 'package:your_app/core/localization/localization_extension.dart';
import 'package:your_app/core/theme/theme.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_detail_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_detail_state.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_action_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_action_state.dart';

class FeatureDetailPage extends StatelessWidget {
  const FeatureDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<FeatureDetailCubit>()..loadDetail(id: id),
        ),
        BlocProvider(create: (_) => getIt<FeatureActionCubit>()),
      ],
      child: const _FeatureDetailView(),
    );
  }
}

class _FeatureDetailView extends StatelessWidget {
  const _FeatureDetailView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: MultiBlocListener(
          listeners: [
            BlocListener<FeatureActionCubit, FeatureActionState>(
              listenWhen: (p, c) => p.status != c.status,
              listener: _onActionStatusChanged,
            ),
          ],
          child: const Column(
            children: [
              _DetailNavBar(),
              Expanded(child: _DetailBody()),
            ],
          ),
        ),
      ),
    );
  }

  void _onActionStatusChanged(BuildContext context, FeatureActionState state) {
    if (state.status == BlocStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.localization.featureActionSuccess),
      ));
      // Reload the detail so the UI reflects the new server state.
      // context.read is correct here — we're in a callback, not build.
      context.read<FeatureDetailCubit>().refreshDetail();
    }
  }
}

class _DetailNavBar extends StatelessWidget {
  const _DetailNavBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.spacing.pagePadding,
        context.spacing.gapNormal,
        context.spacing.pagePadding,
        context.spacing.gapTight,
      ),
      child: Row(
        children: [
          Semantics(
            identifier: 'feature-detail-back',
            button: true,
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).canPop() ? context.pop() : null,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: context.iconSize.chevron,
              ),
              label: Text(
                context.localization.commonBack,
                style: context.styles.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeatureDetailCubit, FeatureDetailState>(
      buildWhen: (prev, curr) =>
          prev.status != curr.status || prev.detail != curr.detail,
      builder: (context, state) {
        return switch (state.status) {
          BlocStatus.initial || BlocStatus.loading => Center(
              child: CircularProgressIndicator(color: context.colors.primary),
            ),
          BlocStatus.failure => _LoadError(failure: state.error),
          BlocStatus.success when state.detail != null =>
            _DetailContent(detail: state.detail!),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.failure});

  final Failure? failure;

  @override
  Widget build(BuildContext context) {
    // ErrorState = the design-tier error pane (lib/core/widgets/).
    return ErrorState(
      message: failure?.getTitle(context) ??
          context.localization.featureDetailLoadFailed,
    );
  }
}

class _DetailContent extends StatelessWidget {
  const _DetailContent({required this.detail});

  final FeatureDetail detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              context.spacing.pagePadding,
              context.spacing.gapCompact,
              context.spacing.pagePadding,
              context.spacing.pagePadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.title, style: context.styles.headlineMedium),
                SizedBox(height: context.spacing.gapCompact),
                Text(detail.description, style: context.styles.bodyLarge),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.divider)),
          ),
          padding: EdgeInsets.fromLTRB(
            context.spacing.pagePadding,
            context.spacing.gapCozy,
            context.spacing.pagePadding,
            context.spacing.gapCompact,
          ),
          child: _ActionBar(detail: detail),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.detail});

  final FeatureDetail detail;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeatureActionCubit, FeatureActionState>(
      buildWhen: (prev, curr) => prev.status != curr.status,
      builder: (context, state) {
        final isLoading = state.status == BlocStatus.loading;
        // PrimaryButton = the project's design-tier CTA (lib/core/widgets/);
        // it renders its own loading spinner and Semantics node.
        return PrimaryButton(
          semanticsIdentifier: 'feature-detail-action',
          label: context.localization.featureDetailAction,
          isLoading: isLoading,
          onPressed: isLoading
              ? null
              : () => context.read<FeatureActionCubit>().run(id: detail.id),
        );
      },
    );
  }
}
