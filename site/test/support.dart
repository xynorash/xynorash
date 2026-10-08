import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xnash_portfolio/data/projects.dart';
import 'package:xnash_portfolio/services/github_stats.dart';
import 'package:xnash_portfolio/state/app_state.dart';
import 'package:xnash_portfolio/theme/theme_controller.dart';

AppState makeState() => AppState(
      theme: ThemeController(load: () => null, save: (_) {}),
      github: GithubStats(
          client: MockClient((_) async => http.Response('nope', 403))),
    );

/// Index of the page with this full path (fails the test if missing).
int idxOf(String path) {
  final i = kBuffers.indexWhere((b) => b.fullPath == path);
  if (i < 0) throw StateError('no page at $path');
  return i;
}
