// Page use case — one variant per distinct visible state.
// Replace your_app / Items / <feature>. Lives at:
//   lib/widgetbook/use_cases/items_page_use_case.dart
//
// ItemsPage resolves its cubit via `BlocProvider(create: (_) => getIt<ItemsCubit>()..load())`,
// so the fake is registered INTO GetIt (idempotently, per variant) — wrapping
// the page in BlocProvider.value would not stop the page's own create: from
// hitting the real, uninitialized DI graph.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/items/logic/cubit/items_cubit.dart';
import 'package:your_app/features/items/logic/cubit/items_state.dart';
import 'package:your_app/features/items/logic/failures/items_failure.dart';
import 'package:your_app/features/items/logic/models/responses/item_response.dart';
import 'package:your_app/features/items/ui/pages/items_page.dart';

// Seeded with the exact state a variant shows; no-op overrides for anything
// the page calls so the tile never runs real logic.
class _FakeItemsCubit extends Cubit<ItemsState> implements ItemsCubit {
  _FakeItemsCubit(super.state);

  @override
  Future<void> load() async {}

  @override
  Future<void> refresh() async {}
}

void _ensureFake(ItemsState state) {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ItemsCubit>()) {
    getIt.unregister<ItemsCubit>();
  }
  getIt.registerFactory<ItemsCubit>(() => _FakeItemsCubit(state));
}

const _kSampleItems = [
  ItemResponse(id: '1', name: 'First item'),
  ItemResponse(id: '2', name: 'Second item'),
];

@widgetbook.UseCase(name: 'default', type: ItemsPage)
Widget itemsPageDefault(BuildContext context) {
  _ensureFake(const ItemsState(status: BlocStatus.success, items: _kSampleItems));
  return const ItemsPage();
}

@widgetbook.UseCase(name: 'loading', type: ItemsPage)
Widget itemsPageLoading(BuildContext context) {
  _ensureFake(const ItemsState(status: BlocStatus.loading));
  return const ItemsPage();
}

@widgetbook.UseCase(name: 'empty', type: ItemsPage)
Widget itemsPageEmpty(BuildContext context) {
  _ensureFake(const ItemsState(status: BlocStatus.success));
  return const ItemsPage();
}

@widgetbook.UseCase(name: 'error', type: ItemsPage)
Widget itemsPageError(BuildContext context) {
  _ensureFake(const ItemsState(
    status: BlocStatus.failure,
    error: ItemsUnknownFailure(),
  ));
  return const ItemsPage();
}
