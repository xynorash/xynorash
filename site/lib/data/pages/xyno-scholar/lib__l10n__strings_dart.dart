import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/l10n/strings.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'strings.dart — fifty strings, each born with both languages'),
    cm('//', 'bilingual UI copy without intl, and the copy that kept lying to be fixed'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'all localisable UI text, as getters on one tiny class'),
    kv('language', 'Dart'),
    kv('size', '116 lines; 50 getters, French and English side by side'),
    kv('history', 'four commits: 7a200e7 (scaffold), c1b3d71, ebafa0f, 98e7e48 — all on 2026-08-06'),
    kv('pinned by', 'test/widget_test.dart expects the French unlock title'),
    ...sec('the decision'),
    ...para('//',
        'The file opens with a sentence that is also a design '
        'decision, and it records why the obvious tool was not used:'),
    ...code('dart', 'lib/l10n/strings.dart · the class', r'''
/// Lightweight bilingual UI copy — deliberately not full `intl`/ARB tooling,
/// since this is a single-user app with exactly two UI languages.
class AppStrings {
  final String language;
  const AppStrings(this.language);

  bool get _fr => language == 'fr';'''),
    ...para('//',
        'Flutter’s official route is intl with ARB files and generated '
        'code: a separate file per language, a code generator, a '
        'build step. That machinery pays off with many languages, '
        'plural rules and translators who never open Dart. Here there '
        'are exactly two languages and one author, so the comment '
        'chooses the opposite trade: no generator, no ARB, nothing to '
        'keep in sync with a build step, and the cost of a new '
        'string is one line.'),

    ...sec('the pattern, and what it makes impossible'),
    ...code('dart', 'lib/l10n/strings.dart · a typical pair', r'''
  String get appTitle => 'Xyno Scholar';
  String get appSubtitle =>
      _fr ? 'Découverte de sujets de recherche' : 'Research topic discovery';'''),
    ...para('//',
        'Every string is a getter whose body is a ternary on _fr. '
        'The one property that matters follows from the syntax: a '
        'ternary needs both branches. It is impossible to add a '
        'French string and forget the English, or the reverse, '
        'because the file does not compile. With ARB files a missing '
        'key in one language is a runtime fallback or a lint; here '
        'it cannot exist. Of the 50 getters, 49 branch on _fr; only '
        'appTitle, a proper noun, is the same in both. One more, '
        'bibtexDialogTitle, has identical text in both branches '
        '(“Export BibTeX”), so it is a pair only in form.'),
    ...para('//',
        'The class is const and holds only the language code. Widgets '
        'create it on the fly where they need text: fifteen call '
        'sites in lib/ do final s = AppStrings(language), usually '
        'from prefs.language. There is no provider and no '
        'InheritedWidget; it is a pure function of one string, so '
        'it costs nothing to rebuild.'),

    ...sec('copy that carries a promise'),
    ...para('//',
        'Most of the file is labels. The exception is the unlock '
        'screen’s explanation of what happens to the API key, '
        'because that sentence is a security claim made to the '
        'user, and its history shows the claim being kept true as '
        'the architecture moved under it.'),
    ...code('dart', 'lib/l10n/strings.dart · unlockSubtitle (wrapped)', r'''
  String get unlockSubtitle => _fr
      ? 'Votre clé reste dans ce navigateur. Elle n\'est envoyée qu\'avec chaque requête,
via un relais sans état, jusqu\'à Mistral — jamais stockée nulle part ailleurs.'
      : 'Your key stays in this browser. It is only ever sent with each request,
via a stateless relay, to Mistral — never stored anywhere else.';'''),
    ...para('//',
        'In the scaffold commit (7a200e7, Cerebras) the English '
        'read “Your key stays in this browser — it is never sent '
        'anywhere but Cerebras.” When the project moved to Gemini '
        '(ebafa0f) the last word became Google. The Mistral commit '
        '(98e7e48) changed the shape of the sentence, not just the '
        'name: Mistral’s endpoint does not answer browser preflight '
        'requests, so requests now pass through a Cloudflare Worker '
        'relay, and “never sent anywhere but Mistral” would have been '
        'false. The new copy says the key is sent with each request, '
        'via a stateless relay, to Mistral. The claim was narrowed '
        'to match the truth rather than left as marketing.'),
    blank,
    ...para('//',
        'The same commit trail touches four other getters, all '
        'provider-branded: unlockTitle, apiKeyLabel, keyRejected and '
        'getApiKeyLink (added in the Gemini commit and rewritten in '
        'the Mistral one to “Get a key from console.mistral.ai”). '
        'Three providers in one day means those lines went through '
        'up to three versions. That is the argument for leaving the '
        'provider name as a literal in the copy: it is cheap to '
        'change, but the widget test is the only thing that '
        'notices if it is stale, and it checks just the title.'),

    ...sec('strings that came and went: the streaming status'),
    ...para('//',
        'The log has a small archaeological layer. The streaming '
        'commit (c1b3d71, 10:28 UTC) added two things to this file: '
        'a getter, connecting (“Connexion à Cerebras…”), and a '
        'method receiving(int chars) that rendered “Receiving… 1 234 '
        'characters”, together with a private _formatCount that '
        'inserted a space every three digits. It was a live progress '
        'indicator for a streamed response, wired into the output '
        'panel, the Generate button and the Refine button. The Gemini '
        'commit (ebafa0f, 10:52 UTC, about 24 minutes later) '
        'removed streaming, and with it deleted all three. The '
        'commit message says loading states went “back to a plain '
        'indeterminate spinner + static status text”. Today the '
        'only progress strings are generateButton and generating.'),
    ...code('dart', 'lib/l10n/strings.dart · what remains', r'''
  // Generate
  String get generateButton => _fr ? 'Générer des sujets' : 'Generate topics';
  String get generating => _fr ? 'Génération en cours…' : 'Generating…';'''),

    ...sec('words that were chosen, not translated'),
    ...code('dart', 'lib/l10n/strings.dart · a few judgement calls', r'''
  String get deepDive => _fr ? 'Approfondir →' : 'Deep Dive →';
  String get saveToNotebook =>
      _fr ? 'Enregistrer au carnet' : 'Save to Notebook';
  String get copyProblematique =>
      _fr ? 'Copier la problématique' : 'Copy problématique';
  String get tabOutline => _fr ? 'Plan en 3 parties' : '3-Part Outline';'''),
    ...para('//',
        'Notice that the English copy keeps “problématique” '
        'in French. There is no neat English equivalent, and the '
        'prompt itself uses the word in English text (“one precise, '
        'tractable problématique”). “Carnet” is the notebook. The '
        'tab title bakes the number three into the string, which is '
        'the same constant as the prompt’s three outline parts and '
        'the model’s three-element array: change one and the '
        'label is wrong. And the arrow is part of the string, so '
        'a translator would not be able to drop it without editing '
        'code, which is fine with one translator.'),

    ...sec('where localisation is not in this file'),
    ...para('//',
        'AppStrings is the main mechanism but not the only one. '
        'Three parallel conventions coexist. Labels for enum values '
        'live on the enums (labelFr and labelEn in enums.dart) and '
        'field names live in the catalog (field_catalog.dart). Short '
        'lists of example prompts and refinement presets are '
        'private constants chosen with an inline ternary '
        '(free_text_panel_card.dart, refine_tab.dart). And a few '
        'one-off words are decided in the widget (the source-type '
        'chips in bibliography_tab.dart). Ten places outside this '
        'file compare language to ‘fr’ by hand, spread over six '
        'files. None is wrong, but a translator looking for “all '
        'the French” would have to know about five files besides '
        'this one.'),
    blank,
    ...para('//',
        'The larger gap is the one this file cannot fix. Error '
        'messages are written in English inside the client and '
        'controller (for example “Could not reach Mistral. Check your '
        'connection and try again.”) and are shown unchanged by the '
        'error banner, so a French session can display an English '
        'error. The key-rejection path is the exception, since '
        'it shows keyRejected from this file.'),

    ...sec('what is tested'),
    ...para('//',
        'One test touches this file, and it does so by accident of '
        'being the first thing on screen: test/widget_test.dart '
        'expects find.text(‘Entrez votre clé API Mistral’), the '
        'French unlockTitle. It was edited in both provider swaps '
        'that changed that line (ebafa0f and 98e7e48). There is no '
        'test that every getter returns different text for fr and '
        'en, or that no string is empty; the ternary form makes the '
        'first worry mostly moot.'),

    ...sec('limits and what is next'),
    ...pt('//', 'three mechanisms',
        'moving enum labels, catalog labels and presets behind '
        'AppStrings would put all the copy in one file.'),
    ...pt('//', 'English-only errors',
        'client and controller messages bypass localisation.'),
    ...pt('//', 'repeated constants',
        'the numbers 3 and 5–8 appear in copy, prompt and parser.'),
    ...pt('//', 'no plural or format support',
        'there is none and, with these strings, none is needed; the '
        'streaming counter was the only formatted string the file '
        'ever had and it was deleted.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
