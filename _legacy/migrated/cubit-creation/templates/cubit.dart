// Standard process-status cubit — injected repository, request/response.
//
// Lives at:
//   lib/features/<feature>/logic/cubit/<feature>_cubit.dart

import 'package:bloc/bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:your_app/core/utils/bloc_status.dart';
import 'package:your_app/features/<feature>/logic/cubit/<feature>_state.dart';
import 'package:your_app/features/<feature>/logic/repositories/<feature>_repository.dart';

@injectable
class FeatureCubit extends Cubit<FeatureState> {
  FeatureCubit(this._repository) : super(const FeatureState());

  final FeatureRepository _repository;

  Future<void> loadData() async {
    emit(state.copyWith(status: BlocStatus.loading));

    final result = await _repository.fetchThing();
    result.fold(
      (failure) {
        emit(state.copyWith(status: BlocStatus.failure, error: failure));
        addError(failure, StackTrace.current); // routes to AppBlocObserver
      },
      (data) => emit(state.copyWith(
        status: BlocStatus.success,
        data: data,
      )),
    );
  }
}
