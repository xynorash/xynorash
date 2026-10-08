import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/services/sanitize.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'sanitize.dart — decoding the entities a model should never emit'),
    cm('//', '28 lines, one recursive function, one bug that looked like bad JSON'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'cleans every string in a decoded model reply before the UI sees it'),
    kv('language', 'Dart'),
    kv('size', '28 lines, 1 public function'),
    kv('depends on', 'package:html_unescape 2.0.0'),
    kv('pinned by', 'test/sanitize_test.dart, added in c1b3d71'),
    ...sec('the problem it solves'),
    ...para('//',
        'The app asks a language model for JSON, and rule 8 of the '
        'system prompt in lib/services/mistral_client.dart says in '
        'capital letters what the output must not contain: raw HTML '
        'tags, and HTML or numeric character entities, with two '
        'examples, the numeric entity for a light bulb and the '
        'ampersand entity. The rule exists because models sometimes '
        'write an emoji or an ampersand as an entity, and Flutter '
        'does not render entities: the reader would see the literal '
        'characters on the screen.'),
    ...para('//',
        'A prompt is a request, not a guarantee. This file is the '
        'second layer, the one that does not depend on the model '
        'behaving. After the reply is parsed, every string in it is '
        'decoded, so a slip like the light-bulb entity or the '
        'ampersand entity turns into the real character before any '
        'widget gets the text. The pattern is trust but verify: ask '
        'nicely in the prompt, repair mechanically in code.'),
    ...sec('the function'),
    ...code('dart', 'lib/services/sanitize.dart · sanitizeJsonTree (trimmed)', r'''
final _unescape = HtmlUnescape();

dynamic sanitizeJsonTree(dynamic value) {
  if (value is String) {
    return _unescape.convert(value);
  }
  ...
  if (value is List) {
    return value.map(sanitizeJsonTree).toList();
  }
  return value;
}'''),
    ...para('//',
        'The tree is what jsonDecode produces: maps, lists, strings '
        'and primitives. The function is a small recursive walk. A '
        'string is decoded; a list is mapped element by element; '
        'everything else (numbers, booleans, null) comes back '
        'unchanged. The parameter and the return type are both '
        'dynamic because a decoded JSON tree has no static type. '
        'There is one shared HtmlUnescape instance at file level, so '
        'the lookup tables are built once.'),
    ...para('//',
        'Only values are decoded. Map keys are left alone, which is '
        'right: the keys are the schema’s field names, chosen by the '
        'app and not by the model’s prose.'),
    ...sec('the Map case, and the bug in it'),
    ...code('dart', 'lib/services/sanitize.dart · why the map is built by hand', r'''
    // Built explicitly (rather than via `value.map(...)`) because promoting
    // a `dynamic` value to `Map` via `is Map` loses the `<String, dynamic>`
    // type arguments, so `.map()` on it silently returns `Map<dynamic,
    // dynamic>` — which then fails the `as Map<String, dynamic>` cast at
    // every call site.
    final result = <String, dynamic>{};
    value.forEach((key, v) {
      result[key as String] = sanitizeJsonTree(v);
    });
    return result;'''),
    ...para('//',
        'The comment is the whole story in five lines, and it is '
        'worth reading slowly because it is a real Dart subtlety. '
        'Dart keeps generic type arguments at run time. After the '
        'check value is Map, the compiler knows the value as Map of '
        'dynamic to dynamic. Calling .map on it with a callback that '
        'returns a MapEntry of dynamic to dynamic produces a new map '
        'whose run-time type is exactly that, Map of dynamic to '
        'dynamic, even though the map that went in was a Map of '
        'String to dynamic. At every call site in mistral_client.dart '
        'the result is then cast with as Map<String, dynamic>, and '
        'that cast, which would have succeeded on the original, fails '
        'on the copy.'),
    ...para('//',
        'The fix builds the result as a literal <String, dynamic>{} '
        'and fills it with forEach, so the run-time type is right by '
        'construction. The single key as String cast inside the loop '
        'is safe because JSON object keys are always strings.'),
    ...para('//',
        'The List case does not need the same care. Its result is a '
        'List of dynamic, and the models cast element by element: '
        'fromJson in lib/models/narrow_topic.dart does e as '
        'Map<String, dynamic> on each entry, which works because each '
        'entry is itself a correctly typed map made by this function. '
        'The precision is only needed where something later casts the '
        'whole container.'),
    ...sec('how the bug hid'),
    ...para('//',
        'The scaffold commit (7a200e7, 09:41 UTC on 2026-08-06) had '
        'the one-line version: return value.map((key, v) => '
        'MapEntry(key, sanitizeJsonTree(v))). It compiled, it looked '
        'right, and it failed every time. The commit that fixed it '
        '(c1b3d71, 10:28 UTC, 47 minutes later) describes it plainly: '
        'every successful JSON parse was incorrectly treated as '
        'invalid and forced into the retry path, which then failed '
        'the same way.'),
    ...para('//',
        'The reason it took until then to notice is in the shape of '
        'the caller, which is still in the code today:'),
    ...code('dart', 'lib/services/mistral_client.dart · where the cast lives', r'''
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return sanitizeJsonTree(parsed) as Map<String, dynamic>;
    } catch (_) {'''),
    ...para('//',
        'The sanitiser call and its cast are inside the same try '
        'block as the JSON parse, and the catch-all handler does not '
        'look at what it caught. A TypeError from the cast and a '
        'FormatException from genuinely bad JSON take the same road: '
        'ask the model again, then give up with the message that '
        'Mistral did not return valid JSON even after a retry. The '
        'bug presented as a flaky model, not as a type error. The '
        'commit message says it was found via the new mocked tests; '
        'presumably a test that fed the client a perfectly valid '
        'reply and still got the invalid-JSON failure, which is '
        'exactly the kind of case a mock makes cheap and a live model '
        'makes rare.'),
    ...para('//',
        'The lesson has two halves. One: test the parsing path with '
        'fixed, correct input so that a failure can only be the '
        'code’s fault. Two: a catch-all around a parse and a '
        'transformation merges two different failures into one '
        'symptom. The second half is still true of the code today; '
        'the handler remains as written, and the regression test '
        'below is what guards against the specific cause.'),
    ...sec('two layers of decoding'),
    ...para('//',
        'The same unescaping runs a second time further down the '
        'pipeline. The renderer that draws all model-written prose '
        'decodes again before parsing the markdown:'),
    ...code('dart', 'lib/widgets/common/markdown_text.dart · the render-time net', r'''
    final safeData = _unescape.convert(data);'''),
    ...para('//',
        'Both layers have a reason. Titles are shown with a plain '
        'Text widget, not through the markdown renderer (the prompt '
        'says title fields are plain text), so ingest-time decoding '
        'in this file is the only protection a title gets. Prose goes '
        'through MarkdownText, which re-checks at the last moment. '
        'The cost is that text can be decoded twice. Running this '
        'function with the Dart SDK on the string &amp;lt; returns '
        '&lt;, a single level of decoding; the renderer would then '
        'turn that into a literal less-than sign. A string that was '
        'deliberately encoded two levels deep therefore comes out one '
        'level further decoded than its author meant. For model '
        'output that is a non-issue, since a double-encoded entity is '
        'itself a slip.'),
    ...sec('what it deliberately does not do'),
    ...pt('//', 'it does not strip HTML tags',
        'the prompt forbids raw tags, and this function only decodes '
        'entities. If a model emitted a tag, the text would pass '
        'through unchanged.'),
    ...pt('//', 'it cannot tell a slip from intent',
        'a sentence that deliberately discusses an HTML entity would '
        'be decoded too. For a research-topic generator in the '
        'humanities this is an acceptable loss; for a technical '
        'writing tool it would not be.'),
    ...pt('//', 'it works on strings after parsing',
        'decoding before jsonDecode could corrupt the JSON syntax '
        'itself, for example by turning an encoded quote into a real '
        'one inside a string value. Decoding the tree after the parse '
        'avoids that class of mistake entirely.'),
    ...sec('the test that pins it'),
    ...para('//',
        'test/sanitize_test.dart was added in the same commit as the '
        'fix, and its comment names the cause: This is the exact cast '
        'every call site performs; it must not throw. The test builds '
        'a nested tree (a map holding a map and a list of maps), runs '
        'it through the function, casts the result as Map<String, '
        'dynamic> and checks three decodings: the ampersand entity, '
        'the numeric light-bulb entity and an encoded angle-bracket '
        'pair. See that page for the details.'),
    ...sec('limits and next'),
    ...pt('//', 'one pass',
        'a deeply nested payload is handled by plain recursion, which '
        'is fine for model replies of a few kilobytes and would be '
        'the wrong tool for huge documents.'),
    ...pt('//', 'silent',
        'nothing records that a replacement happened, so there is no '
        'way to measure how often the model ignores rule 8.'),
    ...pt('//', 'the catch-all remains',
        'splitting the parse step from the cast step in '
        'mistral_client.dart would let a real type error surface with '
        'its own message.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
