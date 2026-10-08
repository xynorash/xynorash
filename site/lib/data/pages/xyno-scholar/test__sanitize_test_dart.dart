import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/test/sanitize_test.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'sanitize_test.dart — the regression test for a type-argument bug'),
    cm('//', 'one test, written the day the bug was found, pinning an exact cast'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'regression test for lib/services/sanitize.dart'),
    kv('language', 'Dart, flutter_test (needs no widgets and no browser)'),
    kv('size', '26 lines, 1 test'),
    kv('history', 'one commit: c1b3d71 (10:28 UTC, 2026-08-06), with the fix'),
    kv('imports', 'flutter_test, and sanitize.dart (itself pure Dart)'),
    ...sec('the bug in one sentence'),
    ...para('//',
        'sanitizeJsonTree is meant to decode HTML entities in every '
        'string of a parsed model reply and hand back a '
        'Map<String, dynamic>. In the scaffold version it handed '
        'back a Map<dynamic, dynamic>, and every call site then '
        'failed its cast to Map<String, dynamic>. The commit '
        'message of c1b3d71 spells out the effect: every '
        'successful JSON parse was treated as invalid and forced '
        'into the retry path, which failed the same way. The page '
        'for lib/services/sanitize.dart tells that story from the '
        'code side. This page is about the test: how a 26-line file '
        'pins a failure that the compiler could not see.'),
    ...sec('the fixture, built to look like a decoded reply'),
    ...code('dart', 'test/sanitize_test.dart · the input', r'''
    // Mirrors the shape returned by jsonDecode on a typical API response.
    final decoded = <String, dynamic>{
      'title': 'A &amp; B',
      'nested': <String, dynamic>{'value': '&#128161;'},
      'list': <dynamic>[
        <String, dynamic>{'x': '&lt;ok&gt;'},
      ],
    };'''),
    ...para('//',
        'Every literal carries explicit type arguments, and that '
        'is the whole point. jsonDecode returns objects as '
        'Map<String, dynamic> and arrays as List<dynamic>. A map '
        'literal written without type arguments would be inferred '
        'differently and might not reproduce the runtime types the '
        'real parser produces. By spelling out <String, dynamic> '
        'and <dynamic>, the test builds a tree whose reified types '
        'match what the client really receives, without needing '
        'to call jsonDecode.'),
    ...para('//',
        'The tree is also shaped to reach every branch of the '
        'function under test. The top-level value is a map, so the '
        'Map branch runs. Inside it are a string, a nested map and '
        'a list holding a map, so the String branch, the Map '
        'branch again and the List branch all run, and the '
        'recursion goes three levels deep at its deepest point '
        '(map, list, map).'),
    ...sec('three entities, three ways of writing one character'),
    ...bullet('A &amp; B',
        'a named entity for the ampersand. This is the one the '
        'prompt’s formatting rule mentions as an example of what '
        'the model must not emit.'),
    ...bullet('&#128161;',
        'a decimal numeric reference. 128161 is 0x1F4A1, the '
        'light-bulb emoji, and the same example appears in the '
        'system prompt in lib/services/mistral_client.dart.'),
    ...bullet('&lt;ok&gt;',
        'two named entities that together spell an angle-bracket '
        'pair around ok. They test that decoding produces real '
        'angle brackets, not that anything then interprets them.'),
    ...sec('the assertions and the comment that matters'),
    ...code('dart', 'test/sanitize_test.dart · the checks', r'''
    final sanitized = sanitizeJsonTree(decoded);

    // This is the exact cast every call site performs; it must not throw.
    final result = sanitized as Map<String, dynamic>;
    expect(result['title'], 'A & B');
    expect((result['nested'] as Map<String, dynamic>)['value'], '💡');
    expect(
      ((result['list'] as List).first as Map<String, dynamic>)['x'],
      '<ok>',
    );'''),
    ...para('//',
        'The comment in the middle is the real specification. The '
        'cast on the first line of the block is not incidental '
        'setup; it is the assertion that would have caught the '
        'bug. The two call sites in lib/services/mistral_client.dart '
        'write the same expression, once for the first attempt and '
        'once for the retry:'),
    ...code('dart', 'lib/services/mistral_client.dart · the call site', r'''
      return sanitizeJsonTree(parsed) as Map<String, dynamic>;'''),
    ...para('//',
        'The three expect calls after it check that the decoding '
        'itself works at each depth, and that the cast is repeated '
        'on the nested map and the list element. The nested casts '
        'matter because the models do the same thing when they '
        'read their children, for example fromJson in '
        'lib/models/narrow_topic.dart casting each element to a '
        'map. A bug that fixed only the top level would still be '
        'caught by the second and third assertions.'),
    ...sec('why the old code failed, step by step'),
    ...para('//',
        'The scaffold version of the Map branch was the one-liner '
        'value.map((key, v) => MapEntry(key, sanitizeJsonTree(v))). '
        'In the function the parameter is dynamic. The check '
        'value is Map promotes it to a Map with no type arguments, '
        'which Dart reads as Map<dynamic, dynamic>. Calling .map on '
        'that infers the result type from the callback, and the '
        'callback returns a MapEntry built from a dynamic key and '
        'a dynamic value. The result is therefore created as a '
        'Map<dynamic, dynamic> no matter what the receiver '
        'really was. The later cast to Map<String, dynamic> checks '
        'the reified type arguments and throws a type error. This '
        'reconstruction follows the explanation in the c1b3d71 '
        'commit message and in the comment now sitting in '
        'sanitize.dart, and I confirmed it by experiment.'),
    ...sec('the experiment: put the bug back'),
    ...para('//',
        'To see whether the test really guards the defect, I '
        'copied the pure-Dart parts of the project (models, the '
        'client and the sanitiser) into a scratch package, ran the '
        'test files with package:test standing in for flutter_test, '
        'and swapped the Map branch back to the scaffold one-liner. '
        'Nothing in the repository was changed. Unmodified, all nine '
        'plain-Dart tests pass. With the bug restored, six fail.'),
    ...pt('//', 'this test',
        'fails at the cast, with the message: type _Map<dynamic, '
        'dynamic> is not a subtype of type Map<String, dynamic> in '
        'type cast. It fails before any expect runs, and the '
        'message names both map types, which is the diagnosis.'),
    ...pt('//', 'five client tests',
        'every test in test/mistral_client_test.dart that feeds '
        'the client valid JSON fails with “Mistral did not return '
        'valid JSON, even after a retry.” That is the misleading '
        'symptom the commit message describes.'),
    ...pt('//', 'three tests keep passing',
        'the retry-exhausted test, the 401 test and the 403 test. '
        'They expect an exception, and the bug produces one. A '
        'test that expects failure cannot tell a correct failure '
        'from the bug that fakes it, which is why the sanitiser '
        'needed its own test.'),
    ...para('//',
        'So the test is strict in the useful direction: it fails '
        'at the point of the real defect with the real cause in the '
        'message, instead of a downstream symptom.'),
    ...sec('why this was easy to miss without it'),
    ...para('//',
        'The call site wraps the parse and the sanitise step in a '
        'single try block with a catch-all handler. A type error '
        'from the cast and a format error from genuinely invalid '
        'JSON take the same road to the retry request. In a live '
        'session the bug would look like a model that keeps '
        'returning bad JSON. With a mock that always returns '
        'good JSON, the symptom becomes unmistakable: valid input, '
        'failure anyway. The commit message credits exactly that: '
        'the bug was found via the new mocked tests. This test '
        'then distils the discovery to the smallest input that '
        'reproduces it, with no HTTP client involved.'),
    ...sec('what it does not cover'),
    ...para('//',
        'The fixture exercises the three container and string '
        'branches. By reading the test, these are not checked:'),
    ...bullet('non-string leaves',
        'numbers, booleans and null pass through untouched in the '
        'implementation, but no assertion says so.'),
    ...bullet('keys',
        'only values are decoded. An entity in a key would be left '
        'as written, and the test does not pin that.'),
    ...bullet('empty containers',
        'an empty map or list returns an empty one, unasserted.'),
    ...bullet('already-decoded text',
        'a string containing a literal ampersand or less-than sign '
        'is passed through the same decoder. Whether double '
        'decoding can change meaning is not tested.'),
    ...bullet('lists of strings',
        'the list branch is only reached with a map inside it. The '
        'common real case of keyKeywords, a list of strings, has no '
        'case of its own.'),
    ...para('//',
        'The last item is the most worth adding, because it is '
        'cheap and because the List branch builds its result with '
        'map(...).toList() on a raw List, the same kind of '
        'expression that caused the Map bug. It is harmless there, '
        'since callers cast list elements one at a time, but a '
        'test would make that reasoning explicit.'),
    ...sec('how it is run'),
    ...para('//',
        'The file imports flutter_test for its test and expect '
        'functions but nothing from the widget layer, and the '
        'function under test imports only the html_unescape '
        'package. By the import graph it does not touch package:web, '
        'so it should not need a browser. The README has no testing '
        'section and the deploy workflow does not run tests, so '
        'nothing in the repository says how or whether it runs on '
        'each push.'),
    ...sec('limits and what is next'),
    ...pt('//', 'one test, one failure mode',
        'the file guards the type-argument bug and the three '
        'decodings. It is not a specification of the sanitiser.'),
    ...pt('//', 'not a CI gate',
        'a regression test only helps if it runs. Adding a test '
        'step to .github/workflows/deploy.yml before the build '
        'would make this file do its job on every push.'),
    ...pt('//', 'a stronger fixture',
        'decoding an actual JSON string with jsonDecode inside the '
        'test would remove any doubt that the fixture matches what '
        'the parser produces.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
