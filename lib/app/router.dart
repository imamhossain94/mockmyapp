import 'package:go_router/go_router.dart';

import '../features/ai_generate/ai_generate_screen.dart';
import '../features/editor/editor_screen.dart';
import '../features/home/home_screen.dart';
import '../features/icon_studio/icon_studio_screen.dart';
import '../features/project/new_project_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/store_copy/store_copy_screen.dart';

// Routes deliberately use `builder`, not `pageBuilder`.
//
// `builder` makes go_router emit a platform-adaptive page (MaterialPage on
// Android, CupertinoPage on iOS/macOS). A `CustomTransitionPage` — even one
// that only fades — replaces that with a plain PageRoute and silently drops
// the iOS interactive edge-swipe-to-go-back gesture on every screen. The
// redesign is visual-only, so removing a system gesture to buy a cross-fade is
// not a trade we get to make here.
//
// If a custom transition is ever wanted, install it as a
// `PageTransitionsTheme` on the app theme (which keeps each platform's pop
// semantics) rather than by swapping the page type.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/new-project',
      // `?start=template` opens the template gallery straight away — the home
      // screen's "Start from a template" card.
      builder: (context, state) => NewProjectScreen(
        openTemplates: state.uri.queryParameters['start'] == 'template',
      ),
    ),
    // The AI screenshot generator: a description and screenshots in, a
    // finished project out. It replaces itself with the editor when done.
    GoRoute(
      path: '/ai-generate',
      builder: (context, state) => const AiGenerateScreen(),
    ),
    GoRoute(
      path: '/project/:id',
      // The studio: every screen of the project's first target, side by side.
      builder: (context, state) =>
          EditorScreen(projectId: state.pathParameters['id']!),
    ),
    // A link to one screen opens the studio on that screen's target, with it
    // active.
    GoRoute(
      path: '/project/:id/edit/:screenId',
      builder: (context, state) => EditorScreen(
        projectId: state.pathParameters['id']!,
        screenId: state.pathParameters['screenId']!,
      ),
    ),
    // The listing's words — name, subtitle, keywords, descriptions — for
    // every store, from the editor's project menu and the AI wizard's finish.
    GoRoute(
      path: '/project/:id/store-copy',
      builder: (context, state) =>
          StoreCopyScreen(projectId: state.pathParameters['id']!),
    ),
    // The app's icon — concepts, the design, every store's files — from the
    // editor's project menu and the AI wizard's finish.
    GoRoute(
      path: '/project/:id/icon',
      builder: (context, state) =>
          IconStudioScreen(projectId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
