import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/status_banner.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'status_banner.dart — the error strip, and the error taxonomy behind it'),
    cm('//', 'a small dismissible rose banner; the interesting part is what it is not used for'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'dismissible inline error message shown above the output'),
    kv('language', 'Dart / Flutter, StatelessWidget'),
    kv('size', '44 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('fed by', 'GenerationState.error, set by the generation controller'),
    ...sec('the widget'),
    ...code('dart', 'lib/widgets/output/status_banner.dart · the container', r'''
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.rose.withValues(alpha: 0.4)),
      ),'''),
    ...para('//',
        'It is a plain Container, not a SnackBar or a MaterialBanner. '
        'The code does not say why; presumably a snack bar, which '
        'times out, is the wrong behaviour for an error the user has '
        'to read, and a MaterialBanner is anchored to the Scaffold '
        'rather than to the output column where the failure '
        'happened. The '
        'recipe is the app’s standard tint: rose at 8 per cent for the '
        'fill, 40 per cent for the border, an 8 px radius, an alert '
        'triangle in solid rose, and the message in ordinary ink so '
        'it stays legible. Rose is reserved for errors and destructive '
        'actions, and this is the main place it appears.'),
    ...code('dart', 'lib/widgets/output/status_banner.dart · the dismiss button', r'''
          if (onDismiss != null)
            IconButton(
              icon: Icon(LucideIcons.x, size: 16, color: colors.inkMuted),
              onPressed: onDismiss,
            ),'''),
    ...para('//',
        'onDismiss is optional, so the widget can also be used for '
        'errors that must stay. OutputPanel always passes one, '
        'wired to generationProvider.notifier.clearError. The error '
        'also clears itself: both _run and refine in the '
        'generation controller start with clearError: true, so a '
        'new request wipes the old message before it begins.'),

    ...sec('where the message comes from: three kinds of failure'),
    ...para('//',
        'The banner shows whatever string GenerationState.error '
        'holds. That string is set in exactly three ways, which '
        'amount to a small taxonomy of what can go wrong when an '
        'app calls a language model from a browser.'),
    ...pt('//', 'the key was rejected (401 or 403)',
        'not a banner case at all. The controller forgets the key '
        'and sends the user back to the unlock screen, which shows '
        'its own rose box (key_entry_screen.dart). The banner never '
        'sees it. My reading is that telling someone their key is '
        'wrong while leaving them on a screen that depends on it '
        'would be a dead end; the client’s doc comment says only '
        'that the caller should clear the key and return to the '
        'unlock screen.'),
    ...pt('//', 'a Mistral or network failure',
        'MistralApiException carries a message written to be safe '
        'to show: its doc comment says it “never includes the key”. '
        'Examples in the client are “Could not reach Mistral. Check '
        'your connection and try again.”, “Mistral returned an error '
        '(HTTP 500). Please try again.” and “Mistral did not return '
        'valid JSON, even after a retry.”'),
    ...pt('//', 'anything else',
        'the controller’s catch-all supplies a fixed sentence: '
        '“Something went wrong while talking to Mistral.” for '
        'generate and deep dive, “Something went wrong while '
        'refining this topic.” for refine.'),
    blank,
    ...para('//',
        'All of these strings are English. The French UI shows an '
        'English banner for every one of them. The localised '
        'genericError in strings.dart is used by the notebook drawer, '
        'not here. This is the clearest gap in the bilingual design '
        'and the reason it is worth stating plainly: the strings '
        'file covers what the widgets say, and these messages '
        'originate below the widgets.'),

    ...sec('a recipe in three copies'),
    ...para('//',
        'The rose tint appears in three hand-built places that '
        'share the same numbers: this banner, the unlock screen’s '
        'rejection box (key_entry_screen.dart) and the excluded-theme '
        'chips in the sidebar (excluded_fields_card.dart, which uses '
        '0.35 for its border instead of 0.4). The amber tint is '
        'likewise built twice, for the clarifying question and the '
        'field suggestion. A single TintedBanner widget with a '
        'colour argument would collapse five Containers. The reason '
        'it has not happened is not stated; the cost of the '
        'duplication so far is small, since the values have not '
        'drifted much.'),

    ...sec('what is tested'),
    ...para('//',
        'The exceptions that feed the banner are tested at the '
        'client: test/mistral_client_test.dart asserts that a second '
        'invalid-JSON reply throws MistralApiException and that '
        '401 and 403 throw ApiKeyRejectedException. The banner '
        'itself, and the controller’s catch-alls, are not tested.'),

    ...sec('limits and what is next'),
    ...pt('//', 'untranslated messages',
        'client and controller strings bypass AppStrings.'),
    ...pt('//', 'no retry action',
        'the banner offers dismiss only; a “Try again” button would '
        'turn a failure into a continuation.'),
    ...pt('//', 'raw status codes',
        'the HTTP code appears in the message for non-200 replies, '
        'which is useful to the owner and opaque to others.'),
    ...pt('//', 'duplicated tint recipe',
        'five hand-built tinted Containers could share one widget.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
