// Detail page — single entity with sub-sections, action bar, and side effects.
//
// Lives at:
//   lib/features/<feature>/ui/pages/<feature>_detail_page.dart
//
// Pairs with:
//   /cubit-creation         (FeatureDetailCubit + FeatureDetailState; also
//                            secondary cubits like an action cubit)
//   /widget-creation        (extracting _FeatureHero, _ActionBar, etc.)
//   /navigation-gorouter    (route params arriving as constructor args)
//   /failure-modeling       (the Failure used in error rendering)
//
// Conventions illustrated:
//   - MultiBlocProvider supplies multiple cubits (detail + action cubits).
//   - MultiBlocListener handles side effects (snackbars, dialogs, refresh-after-
//     action) with listenWhen narrowed per listener.
//   - BlocBuilder at the section level — never the whole page — with buildWhen.
//   - Status switch differentiates loading / failure / success(detail!).
//   - context.read<Cubit>() only in callbacks (the cancel/confirm taps).
//   - Semantics(identifier:) wraps the interactable (back button, action button,
//     modal, modal-dismiss).

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
          child: Column(
            children: const [
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
      // After a successful action, reload the detail so the UI reflects the new
      // server state. Use context.read here — we're in a callback, not build.
      context.read<FeatureDetailCubit>().refreshDetail();
    }
  }
}

class _DetailNavBar extends StatelessWidget {
  const _DetailNavBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSize.s20,
        AppSize.s12,
        AppSize.s20,
        AppSize.s4,
      ),
      child: Row(
        children: [
          Semantics(
            identifier: 'feature-detail-back',
            button: true,
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).canPop() ? context.pop() : null,
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: AppSize.s14,
              ),
              label: Text(
                context.localization.commonBack,
                style: context.styles.subtitle,
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
          BlocStatus.failure => const _LoadError(),
          BlocStatus.success when state.detail != null =>
            _DetailContent(detail: state.detail!),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSize.s20),
        child: Text(
          context.localization.featureDetailLoadFailed,
          textAlign: TextAlign.center,
          style: context.styles.subtitle,
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(
              AppSize.s20,
              AppSize.s8,
              AppSize.s20,
              AppSize.s20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.title, style: context.styles.headlineMedium),
                const SizedBox(height: AppSize.s8),
                Text(detail.description, style: context.styles.bodyLarge),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.colors.divider)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSize.s20,
            AppSize.s16,
            AppSize.s20,
            AppSize.s8,
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
        return Semantics(
          identifier: 'feature-detail-action',
          button: true,
          child: FilledButton(
            onPressed: isLoading
                ? null
                : () => context.read<FeatureActionCubit>().run(id: detail.id),
            child: isLoading
                ? const SizedBox(
                    width: AppSize.s16,
                    height: AppSize.s16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.localization.featureDetailAction),
          ),
        );
      },
    );
  }
}
