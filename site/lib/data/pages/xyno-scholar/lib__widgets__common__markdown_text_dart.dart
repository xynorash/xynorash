import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/common/markdown_text.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'markdown_text.dart — the one door every generated sentence walks through'),
    cm('//', 'a themed markdown renderer, and the last of three defences against HTML entities'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'shared renderer for every AI-written prose field in the UI'),
    kv('language', 'Dart / Flutter, flutter_markdown with GitHub-flavoured extensions'),
    kv('size', '79 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); never touched afterwards'),
    kv('used by', 'output panel, broad cards, narrow view, three tabs, notebook drawer'),
    ...sec('why this file exists'),
    ...para('//',
        'The model is allowed to write light markdown: bold, italics, '
        'short lists. If each widget handled that on its own, every '
        'screen would have a slightly different idea of what bold '
        'looks like. This file is the single place that turns a '
        'generated string into styled text, which is why its doc '
        'comment lists the fields it serves:'),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · the contract', r'''
/// Shared renderer for every AI-generated prose field (pitch,
/// whyFitsAllFields, levelNotes, fieldsIntersectionExplanation, relevance,
/// outline descriptions, refinementSummary, clarifyingQuestion). GFM
/// extensions enabled, custom styling pulled from the app theme, with an
/// entity-decoding safety net in case a raw entity ever slips through.
class MarkdownText extends StatelessWidget {'''),
    ...para('//',
        'Read the list as a map of the data model. Every field named '
        'is a prose field in lib/models. The fields that are absent '
        'are the titles, which the prompt declares plain text, and '
        'the problématique, which the prompt does not classify but '
        'which the dark callout draws as plain text. The prompt’s '
        'own rule splits the schema in two:'),
    ...code('dart', 'lib/services/mistral_client.dart · system prompt, rule 8 (wrapped)', r'''
   - Title fields are plain text: no Markdown, no emoji.
   - Prose fields (pitch, explanations, relevance notes, descriptions)
may use light Markdown (bold/italic/short lists) and nothing more elaborate.'''),
    ...para('//',
        'The widgets follow the same division. Titles are drawn with '
        'a Text widget in the serif face, and the problématique '
        'is a plain Text in its dark callout. Everything else goes '
        'through MarkdownText. The consequence is visible: a stray '
        'asterisk in a title would show up literally rather than as '
        'emphasis.'),

    ...sec('the safety net'),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · build', r'''
    final colors = context.colors;
    final safeData = _unescape.convert(data);

    return MarkdownBody(
      data: safeData,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,'''),
    ...para('//',
        'The first line of real work is html_unescape on the data, '
        'before the markdown parser sees it. That is the third layer '
        'of defence against one specific failure: the model emitting '
        'an HTML entity (“&#128161;” for a lamp emoji, “&amp;” for an '
        'ampersand) in spite of being told not to. Layer one is the '
        'prompt itself, which forbids entities and tells the model to '
        'use the real Unicode character. Layer two is sanitizeJsonTree '
        'in lib/services/sanitize.dart, which decodes every string in '
        'the parsed JSON tree before any model class is built. Layer '
        'three is here, “in case a raw entity ever slips through”, '
        'as the comment says.'),
    blank,
    ...para('//',
        'Is the third layer redundant? Almost certainly, for output '
        'that went through the client, since layer two already ran. '
        'But the cost is one function call on short strings, and the '
        'widget does not have to trust that its caller sanitised. '
        'There is a small price: decoding twice would also decode '
        'text that legitimately contains an entity-shaped sequence, '
        'for instance a topic about HTML itself. For this app’s '
        'subject matter that is a very remote case.'),
    ...para('//',
        'selectable: true matters more than it looks. The student '
        'wants to copy a sentence from a pitch into their notes, and '
        'the default MarkdownBody is not selectable; this one is, '
        'so the generated text behaves like text on a web page.'),

    ...sec('styling: the theme, restated for markdown'),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · paragraph style', r'''
        p: AppTypography.sans(
          fontSize: 15,
          color: colors.ink,
        ).copyWith(height: 1.55),'''),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · links and blockquotes', r'''
        a: AppTypography.sans(
          weight: FontWeight.w600,
          fontSize: 15,
          color: colors.teal,
        ).copyWith(decoration: TextDecoration.underline),
        blockquote: AppTypography.serif(
          style: FontStyle.italic,
          fontSize: 16,
          color: colors.inkMuted,
        ),
        blockquoteDecoration: BoxDecoration(
          color: colors.parchment,
          border: Border(left: BorderSide(color: colors.amber, width: 3)),
        ),'''),
    ...para('//',
        'Every choice repeats the system from the theme files. '
        'Paragraphs are Inter at 15 px with a 1.55 line height, '
        'looser than the default, which suits the long, dense '
        'academic prose the model writes. Links are teal and '
        'underlined, because teal means interactive. Block quotes '
        'switch to the serif italic with an amber left rule on a '
        'parchment panel, the same visual language as a pull quote. '
        'Headings h1 to h3 are serif at 22, 19 and 17 px; code is '
        'JetBrains Mono at 13 px on parchment. The sizes are literals '
        'in this stylesheet rather than theme roles, which is the '
        'duplication the typography page notes.'),

    ...sec('links: opened outside the app, not filtered'),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · onTapLink', r'''
      onTapLink: (text, href, title) {
        if (href == null) return;
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },'''),
    ...para('//',
        'A tapped link opens in a new tab (externalApplication), so '
        'the app and the unsaved topic stay put. Two things are '
        'worth knowing. There is no scheme allow-list: any href the '
        'model puts in a markdown link is passed to launchUrl. And '
        'Uri.parse throws on a malformed string, with no try around '
        'it. The prompt asks for “light Markdown (bold/italic/short '
        'lists) and nothing more elaborate”, so links are not '
        'expected; the renderer is more capable than the contract '
        'it serves. The text comes from a request made with the '
        'user’s own key, so I would call the risk small, but it is '
        'the one place where model text can trigger an action.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ builds a MarkdownText. The sanitiser it '
        'backs up has its own regression test (test/sanitize_test.dart, '
        'which pins that a decoded tree still casts to '
        'Map<String, dynamic> and that “&amp;”, “&#128161;” and '
        '“&lt;ok&gt;” decode to the expected characters), but '
        'the widget’s unescape call, the link handler and the '
        'stylesheet are only exercised by looking at the app.'),

    ...sec('limits and what is next'),
    ...pt('//', 'double decoding',
        'harmless for this content, wrong in principle; one layer '
        'would be cleaner if the callers could be trusted.'),
    ...pt('//', 'no link policy',
        'an allow-list of http and https and a try around Uri.parse '
        'would harden the one tap handler.'),
    ...pt('//', 'literal sizes',
        'heading and body sizes are hard-coded in the stylesheet.'),
    ...pt('//', 'no widget test',
        'a golden test with bold, a list and an entity would pin the '
        'rendering.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
