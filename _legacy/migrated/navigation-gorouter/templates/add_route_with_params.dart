// Adding a route with arguments — covers the three argument channels.
//
//   Path params (/x/:id)      — required identity; deeplink-encodable
//   Query params (?mode=x)    — optional flags; deeplink-encodable
//   state.extra (rich object) — in-app only; NOT deeplink-encodable
//
// Pick the right channel per arg. If a deeplink should be able to reach the
// page, the data MUST live in path or query — extra is for in-app navigation.
//
// This template shows a "promotion details" route that takes:
//   • promotionId (path param — required identity)
//   • mode=preview (query — optional, when the user is previewing a draft)
//   • promotionPreview (state.extra — the full draft object, only set when
//     navigating from the editor in-app; cold-start deeplink falls back to
//     loading by ID)
//
// The per-route redirect demonstrates validating one argument before allowing
// render — mirrored on `accountScheduledForDeletion` in router.dart.

// ─── STEP 1: routes.dart ─────────────────────────────────────────────────────
//
// enum AppRoutes {
//   // ...existing...
//   promotionDetails('PromotionDetails', '/promotions/:promotionId'),
// }

// ─── STEP 2: router.dart, inside the authenticated routes section ────────────
//
// GoRoute(
//   name: AppRoutes.promotionDetails.name,
//   path: AppRoutes.promotionDetails.path,
//   parentNavigatorKey: rootNavigatorKey,
//
//   // (Optional) per-route redirect: validates args before render.
//   // Returning null = render. Returning a path = redirect there instead.
//   redirect: (ctx, state) {
//     final id = state.pathParameters['promotionId'];
//     if (id == null || id.isEmpty) {
//       // Path-pattern guarantees `promotionId` is present; this branch is
//       // belt-and-suspenders for malformed deeplinks.
//       return AppRoutes.home.path;
//     }
//     return null;
//   },
//
//   pageBuilder: (context, state) {
//     final promotionId = state.pathParameters['promotionId']!;
//     final isPreview = state.uri.queryParameters['mode'] == 'preview';
//     final preview = state.extra is PromotionPreview
//         ? state.extra! as PromotionPreview
//         : null;
//
//     return CupertinoPage(
//       // Key includes the id so a navigate-from-detail-to-detail rebuilds
//       // the page rather than reusing the previous instance.
//       key: ValueKey('${AppRoutes.promotionDetails.path}/$promotionId'),
//       child: PromotionDetailsPage(
//         promotionId: promotionId,
//         isPreview: isPreview,
//         preview: preview,
//       ),
//     );
//   },
// ),

// ─── STEP 3: navigation call site ────────────────────────────────────────────
//
// // Standard drill-in (loads by id):
// context.pushNamed(
//   AppRoutes.promotionDetails.name,
//   pathParameters: {'promotionId': promotion.id},
// );
//
// // With a query flag:
// context.pushNamed(
//   AppRoutes.promotionDetails.name,
//   pathParameters: {'promotionId': promotion.id},
//   queryParameters: {'mode': 'preview'},
// );
//
// // With extra (in-app only — the editor passes the draft directly):
// context.pushNamed(
//   AppRoutes.promotionDetails.name,
//   pathParameters: {'promotionId': draftId},
//   queryParameters: {'mode': 'preview'},
//   extra: PromotionPreview(/* ... */),
// );

// ─── Page widget — accepts the args via constructor ──────────────────────────

import 'package:flutter/material.dart';
import 'package:core_boilerplate/core/injection/injection.dart';
import 'package:core_boilerplate/core/theme/theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PromotionDetailsPage extends StatelessWidget {
  const PromotionDetailsPage({
    required this.promotionId,
    this.isPreview = false,
    this.preview,
    super.key,
  });

  final String promotionId;
  final bool isPreview;

  /// In-memory draft passed via `state.extra` when navigating from the editor.
  /// Null for deeplink entries — the cubit will fetch by id instead.
  final PromotionPreview? preview;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = getIt<PromotionDetailsCubit>();
        // Use the in-memory draft when available; fall back to fetching by id.
        if (preview != null) {
          cubit.loadFromPreview(preview!);
        } else {
          cubit.loadById(promotionId, isPreview: isPreview);
        }
        return cubit;
      },
      child: const _PromotionDetailsView(),
    );
  }
}

class _PromotionDetailsView extends StatelessWidget {
  const _PromotionDetailsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: const [
            // Page content — see /page-creation for the full shape
          ],
        ),
      ),
    );
  }
}

// Stand-ins so the template type-checks. Real versions live in your feature.
class PromotionPreview {}
class PromotionDetailsCubit extends Cubit<Object> {
  PromotionDetailsCubit() : super(Object());
  void loadFromPreview(PromotionPreview preview) {}
  void loadById(String id, {bool isPreview = false}) {}
}
