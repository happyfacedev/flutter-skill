// Adding a simple route — no params, full-screen drill-in (covers the bottom nav).
//
// Three locations to edit:
//   1. lib/core/router/routes.dart            — add the AppRoutes enum entry
//   2. lib/core/router/router.dart            — add the GoRoute definition
//   3. (call site) wherever you navigate to it — use AppRoutes.x.name, never a string
//
// If the route should be reachable when logged out, ALSO add the enum value to
// `unauthenticatedRoutes` (or `unverifiedRoutes` / `publicRoutes`) inside
// routes.dart. Otherwise leave it out — anything not in a group is treated as
// authenticated.
//
// This template shows a full-screen settings subpage (drill-in, hides the
// bottom nav when one exists). For routes that should keep the bottom nav
// visible, see the StatefulShellRoute.indexedStack section of router.dart
// instead.

// ─── STEP 1: routes.dart ─────────────────────────────────────────────────────
//
// enum AppRoutes {
//   // ...existing...
//   activityHistory('ActivityHistory', '/settings/activity-history'),
// }

// ─── STEP 2: router.dart, inside the authenticated routes section ────────────
//
// GoRoute(
//   name: AppRoutes.activityHistory.name,
//   path: AppRoutes.activityHistory.path,
//   parentNavigatorKey: rootNavigatorKey,   // <-- hides bottom nav
//   pageBuilder: (context, state) => CupertinoPage(
//     key: ValueKey(AppRoutes.activityHistory.path),
//     child: const ActivityHistoryPage(),
//   ),
// ),

// ─── STEP 3: navigation call site ────────────────────────────────────────────
//
// // Drill-in (back returns to the previous page):
// context.pushNamed(AppRoutes.activityHistory.name);
//
// // Lateral / replace (e.g., reached from a deep link):
// context.goNamed(AppRoutes.activityHistory.name);
//
// // NEVER:
// context.push('/settings/activity-history');   // bare string drifts when path changes

// ─── Page widget (separate file under features/<x>/ui/pages/) ────────────────
// See /page-creation for the page shape. Skeleton for reference:

import 'package:flutter/material.dart';
import 'package:core_boilerplate/core/theme/theme.dart';

class ActivityHistoryPage extends StatelessWidget {
  const ActivityHistoryPage({super.key});

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
