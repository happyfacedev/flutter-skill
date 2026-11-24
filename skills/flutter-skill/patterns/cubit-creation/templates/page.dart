// Page — StatelessWidget hosting BlocProvider; BlocBuilder switches on status.
//
// Lives at:
//   lib/features/<feature>/ui/pages/<feature>_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:your_app/core/injection/injection.dart';   // getIt
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_cubit.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';

class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FeatureCubit>()..loadData(),   // kick off on mount
      child: const Scaffold(
        body: _FeatureContent(),
      ),
    );
  }
}

class _FeatureContent extends StatelessWidget {
  const _FeatureContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeatureCubit, FeatureState>(
      buildWhen: (prev, curr) => prev.status != curr.status,
      builder: (context, state) {
        return switch (state.status) {
          BlocStatus.initial => const SizedBox.shrink(),
          BlocStatus.loading => const Center(child: CircularProgressIndicator()),
          BlocStatus.success => SuccessView(data: state.data),
          BlocStatus.failure => ErrorView(error: state.error),
        };
      },
    );
  }
}
