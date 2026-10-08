import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/screens/key_entry_screen.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'key_entry_screen.dart — the front door: bring your own key'),
    cm('//', 'the only screen shown until a Mistral API key exists in memory'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'BYOK unlock screen: enter, reveal, optionally remember, and re-enter after rejection'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerStatefulWidget'),
    kv('size', '224 lines (179 at the scaffold, 204 after Gemini, 224 after Mistral)'),
    kv('history', 'four commits: 7a200e7, 89a9c12 (icon package), ebafa0f, 98e7e48'),
    kv('pinned by', 'test/widget_test.dart finds the French title text on first run'),
    ...sec('why this screen exists'),
    ...para('//',
        'Xyno Scholar has no backend, so there is nowhere to keep a '
        'shared API key and no way to bill anyone. The user supplies '
        'their own Mistral key, and the app has to ask for it before '
        'it can do anything. This screen is that ask. It sits in front '
        'of everything with one gate and no routing: app.dart renders '
        'HomeScreen when apiKeyProvider says isUnlocked and this '
        'screen otherwise, so “unlocked” is a field of state, not '
        'a place in a navigator.'),
    blank,
    ...para('//',
        'The whole screen is a vehicle for one promise, stated in '
        'the card’s subtitle: the key stays in this browser, goes out '
        'only with each request via a stateless relay to Mistral, and '
        'is never stored elsewhere. Everything below is how the '
        'screen tries not to break that.'),

    ...sec('submitting: small, defensive, ordered'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · _submit', r'''
  void _submit() {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    ref.read(keyRejectedMessageProvider.notifier).state = null;
    ref
        .read(apiKeyProvider.notifier)
        .setKey(key, rememberForSession: _remember);
  }'''),
    ...para('//',
        'Three details. The pasted text is trimmed; the code does '
        'not say why, but stray whitespace on a pasted secret is the '
        'usual reason. An empty field is a silent no-op. And the rejection message '
        'is cleared before the new key is set, so an earlier error '
        'does not linger over a fresh attempt. The same method '
        'serves two triggers: the Continue button and the Enter key '
        '(onSubmitted on the field).'),
    blank,
    ...para('//',
        'Notice what does not happen here. The screen never '
        'navigates. setKey changes provider state, app.dart '
        'rebuilds with isUnlocked true, and this widget is simply '
        'removed from the tree (its controller is disposed in '
        'dispose). The key lives in the TextEditingController '
        'until then and in ApiKeyState afterwards. The only place '
        'the client sends it is the Authorization header of the '
        'request to the relay (see lib/services/mistral_client.dart), '
        'and a search of lib/ finds no print call at all.'),

    ...sec('the field: hidden by default, monospaced when shown'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · the key field', r'''
                              TextField(
                                controller: _controller,
                                obscureText: _obscure,
                                autofocus: true,
                                decoration: InputDecoration(
                                  labelText: s.apiKeyLabel,'''),
    ...para('//',
        'obscureText starts true and the suffix icon toggles it '
        '(eye and eye-off from the Lucide set), a standard pattern '
        'for secrets that lets someone verify a paste when they '
        'choose to. The style is AppTypography.mono at 14 px, one '
        'of only three uses of the monospace family in the app. '
        'autofocus means the first thing a returning user can do '
        'is paste.'),

    ...sec('remember for this session: an opt-in, off by default'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · the switch', r'''
                                  Switch(
                                    value: _remember,
                                    onChanged: (v) =>
                                        setState(() => _remember = v),
                                  ),'''),
    ...para('//',
        '_remember is initialised to false. Turning it on makes '
        'ApiKeyController.setKey also write the key to the '
        'browser’s sessionStorage, so a page refresh does not '
        'throw the user back here; closing the tab clears it. The '
        'README states the boundary: sessionStorage if the user '
        'opts in, never localStorage. The label is deliberately '
        'specific, “Remember for this browser session”, not '
        '“Remember me”, so the copy tells the user how long the '
        'convenience lasts.'),
    ...para('//',
        'There is a link to console.mistral.ai under the field, '
        'opened with LaunchMode.externalApplication so it goes '
        'to a new tab and does not replace the app (and the key '
        'just typed). It was added when the provider was Gemini, '
        'pointing at Google AI Studio, and re-pointed for Mistral.'),

    ...sec('rejection: how a bad key gets back here'),
    ...para('//',
        'This screen is also the landing place for a failed call. '
        'When Mistral answers 401 or 403, MistralClient throws '
        'ApiKeyRejectedException, and the generation controller '
        'handles it by wiping the key:'),
    ...code('dart', 'lib/providers/generation_provider.dart · key rejected', r'''
    } on ApiKeyRejectedException catch (e) {
      ref.read(keyRejectedMessageProvider.notifier).state = e.message;
      ref.read(apiKeyProvider.notifier).forget();'''),
    ...para('//',
        'forget() clears sessionStorage and resets the state, so '
        'isUnlocked flips to false and app.dart swaps this screen '
        'back in, now with keyRejectedMessageProvider non-null. A '
        'rose-tinted box with an alert icon appears above the '
        'field:'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · the rejection box', r'''
                              if (rejectedMessage != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),'''),
    ...para('//',
        'A quirk: the provider holds the exception’s English '
        'message (“Your API key was rejected.”), but the screen '
        'uses it only as a flag and prints s.keyRejected, the '
        'localised string from lib/l10n/strings.dart. That is why '
        'the rejection message is in the user’s language while the '
        'other error messages, shown in the output panel, are not. The '
        'box is built by hand rather than with StatusBanner, '
        'although it uses the same recipe (rose at 8 per cent '
        'fill, 40 per cent border, alert triangle); the two differ '
        'only in small values such as icon size, 16 against 18.'),

    ...sec('the layout bug that rewrote 300 lines'),
    ...para('//',
        'Of the file’s four commits, the Mistral one has the biggest '
        'diff and the least interesting logic. Its message explains: '
        '“Fix a RenderFlex overflow on the unlock screen (longer '
        'link copy pushed the card past the fixed layout height) by '
        'making the screen scrollable while keeping it centered '
        'when content fits”. The original body was a Center around a '
        'Column with mainAxisSize.min, which works until the content '
        'is taller than the viewport, at which point Flutter paints '
        'the yellow-and-black overflow stripes. The fix is the '
        'classic centred-or-scrollable sandwich:'),
    ...code('dart', 'lib/screens/key_entry_screen.dart · build (outer layers)', r'''
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),'''),
    ...para('//',
        'Read it from the inside out. maxWidth 460 keeps the card '
        'a readable column on wide screens. Center puts the content '
        'in the middle of whatever space it is given. The '
        'minHeight constraint, taken from LayoutBuilder, makes '
        'that space at least as tall as the viewport, so a short card '
        'is still centred vertically. And SingleChildScrollView '
        'lets the content exceed the viewport and scroll instead '
        'of overflowing. The git stat for that commit, 300 changed '
        'lines for a handful of wrapper widgets, is mostly '
        're-indentation: wrapping the old body pushed every line '
        'of the form several levels deeper.'),

    ...sec('what is missing: a language switch'),
    ...para('//',
        'This screen reads the language from preferenceBlockProvider '
        'but offers no way to change it. The FR/EN toggle exists only '
        'in the home screen’s app bar (home_screen.dart), and the '
        'preferences reset to French on every page load, so a '
        'visitor who reads English meets a French key screen each '
        'time and can only switch after unlocking. For the owner, '
        'who defaults to French, that is invisible. The widget '
        'test locks the behaviour in on purpose: it expects the '
        'French title, “Entrez votre clé API Mistral”, with no '
        'interaction.'),

    ...sec('what is tested'),
    ...para('//',
        'The single widget test pumps the whole app and asserts '
        'that the French unlock title is on screen. It has been '
        'edited twice (ebafa0f, 98e7e48) because the provider '
        'name is part of that title. Nothing tests submitting, '
        'trimming, the obscure toggle, the remember switch or the '
        'rejection box.'),

    ...sec('limits and what is next'),
    ...pt('//', 'no language switch here',
        'a small FR/EN control would fix the first-impression gap.'),
    ...pt('//', 'duplicated rejection box',
        'reuse StatusBanner or extract a shared widget so the two '
        'error recipes cannot drift.'),
    ...pt('//', 'no key format check',
        'any non-empty text is accepted; a wrong key is learned '
        'only on the first request, with the cost of a round trip.'),
    ...pt('//', 'deep nesting',
        'the build method is indented past column 40 in places; '
        'splitting the card into its own widget would help.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
