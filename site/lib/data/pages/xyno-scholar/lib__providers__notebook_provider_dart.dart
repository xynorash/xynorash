import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/providers/notebook_provider.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'notebook_provider.dart — the one thing the app remembers on purpose'),
    cm('//', 'a saved-topics store, and a race that can overwrite it'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'persistent notebook of saved narrow topics plus the user’s own notes'),
    kv('language', 'Dart, Riverpod 2.6 (AsyncNotifier), shared_preferences'),
    kv('size', '65 lines: 1 controller with 3 mutations, 1 provider'),
    kv('storage', 'key xyno_scholar_notebook_v1, one JSON list, whole-list rewrite'),
    kv('finding', 'saving before the notebook has loaded can erase earlier entries'),
    ...sec('what it is for'),
    ...para('//',
        'Everything else in the app is deliberately forgetful. The '
        'API key lives in memory, the preferences reset on reload, '
        'and a generated topic disappears when the next one arrives. '
        'The notebook is the exception: a place where a user can pin '
        'a narrow topic that looks promising, add their own notes '
        'under it and come back later. It is the only data in the app '
        'that is meant to outlive the session, so it is the only '
        'thing stored durably, and its storage is kept strictly apart '
        'from the key’s. The key may use sessionStorage if the user '
        'opts in; the notebook uses shared_preferences, which on the '
        'web is backed by the browser’s localStorage (the lock file '
        'resolves shared_preferences_web 2.4.3).'),
    ...para('//',
        'What goes in is a NotebookEntry from '
        'lib/models/notebook_entry.dart: a random identifier, the '
        'whole NarrowTopic (title, pitch, research question, level '
        'notes, bibliography, outline), the user’s notes and a '
        'timestamp. No secret is ever part of an entry, which is the '
        'property that makes it safe to keep.'),
    ...sec('loading'),
    ...code('dart', 'lib/providers/notebook_provider.dart · build()', r'''
const _notebookStorageKey = 'xyno_scholar_notebook_v1';
const _uuid = Uuid();

class NotebookController extends AsyncNotifier<List<NotebookEntry>> {
  @override
  Future<List<NotebookEntry>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notebookStorageKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => NotebookEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }'''),
    ...para('//',
        'The controller is an AsyncNotifier because the first read '
        'has to wait for the browser storage to be opened. While the '
        'future is pending the provider is in a loading state, and '
        'the drawer shows a spinner. A failure becomes an error '
        'state, which the drawer renders as a single red sentence. '
        'The storage key ends in _v1, which reads as a version stamp: '
        'a future change to the saved shape could use _v2 and '
        'migrate. No migration exists, and the repository does not '
        'describe a plan.'),
    ...para('//',
        'The whole notebook is one JSON string, a list of entries. '
        'That is simple and correct at this scale, and it determines '
        'the cost model of everything below: every change rewrites '
        'the entire list.'),
    ...sec('the three mutations'),
    ...code('dart', 'lib/providers/notebook_provider.dart · save and persist', r'''
  Future<void> _persist(List<NotebookEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _notebookStorageKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> save(NarrowTopic topic) async {
    final current = state.value ?? [];
    final entry = NotebookEntry(
      id: _uuid.v4(),
      topic: topic,
      personalNotes: '',
      savedAt: DateTime.now(),
    );
    final updated = [entry, ...current];
    state = AsyncData(updated);
    await _persist(updated);
  }'''),
    ...para('//',
        'save() builds an entry with a fresh random version-4 '
        'identifier, puts it at the front of the list so the newest '
        'topic is on top, publishes the new list to the interface '
        'first and only then writes it to storage. That order makes '
        'the UI feel instant, and it is a common optimistic pattern. '
        'It also means that if the write fails, the screen shows an '
        'entry that does not exist in storage; there is no try/catch '
        'to roll the state back, and no error is reported.'),
    ...para('//',
        'The identifier is new on every call, and nothing compares '
        'topics, so saving the same topic twice produces two entries. '
        'That is arguably right for a notebook where notes differ, '
        'and the identifier is what lets remove and updateNotes '
        'target one entry.'),
    ...code('dart', 'lib/providers/notebook_provider.dart · updateNotes', r'''
  Future<void> updateNotes(String id, String notes) async {
    final current = state.value ?? [];
    final updated = [
      for (final e in current)
        if (e.id == id) e.copyWith(personalNotes: notes) else e,
    ];
    state = AsyncData(updated);
    await _persist(updated);
  }'''),
    ...para('//',
        'updateNotes uses a collection-for-with-if to rebuild the '
        'list with one entry replaced, which keeps everything '
        'immutable. The drawer calls it from the notes field’s '
        'onChanged callback, that is, on every keystroke, so each '
        'character typed re-serialises and rewrites the whole '
        'notebook. With a handful of entries this is imperceptible; '
        'the cost grows with the amount of saved text, and there is '
        'no debounce. remove() filters by identifier in the same way.'),
    ...sec('the race: saving before the notebook has loaded'),
    ...para('//',
        'Look again at the first line of save(): state.value ?? []. '
        'It reads the current list from the provider’s state, and '
        'falls back to an empty list when there is none. That is safe '
        'only if the provider has already finished loading by the '
        'time save() runs. Whether it has depends on who touched the '
        'provider first.'),
    ...para('//',
        'The only place that watches the notebook is the drawer, and '
        'Flutter does not build a drawer’s contents until it is '
        'opened. I checked that in the Flutter source: the drawer '
        'controller returns an empty widget while the drawer is '
        'dismissed and builds its child only when it opens. So after '
        'a page load, the notebook provider does not exist until '
        'either the user opens the drawer or something reads it. The '
        'Save to notebook button in the topic view reads it: '
        'ref.read(notebookProvider.notifier).save(topic). Reading the '
        'notifier creates the provider and starts build(), which is '
        'asynchronous, and save() runs straight away, while the state '
        'is still loading. state.value is null, the fallback gives an '
        'empty list, the new list contains only the new entry, and '
        '_persist writes that over whatever the earlier sessions had '
        'saved.'),
    ...para('//',
        'I reproduced the behaviour outside the app. Using the Dart '
        'SDK and the real riverpod 2.6.1 package, I wrote a small '
        'program with the same AsyncNotifier shape and an in-memory '
        'stand-in for shared_preferences, preloaded with two entries. '
        'Two scenarios, one result each.'),
    plain('   A  save() as the first action (provider never read):'),
    plain('      storage afterwards: only the new entry'),
    plain('      provider state: the two old entries (build finished last)'),
    plain('   B  provider loaded first (drawer opened, or awaited):'),
    plain('      storage afterwards: new entry followed by the two old ones'),
    ...para('//',
        'In scenario A the old entries are lost from storage and the '
        'interface, by then, shows the old ones without the new one; '
        'the next mutation writes whichever list is in memory and '
        'erases the other. The snackbar that follows a save says the '
        'topic was saved, which in this sequence is only half true. '
        'This is a replica of the logic and of Riverpod’s semantics, '
        'not a run of the Flutter app, which I did not do. If the '
        'real behaviour matches, the user-visible symptom would be: '
        'first action after a page load is to save a topic, and the '
        'notebook that was full yesterday holds one entry today.'),
    ...para('//',
        'The repair is a single line, because the information needed '
        'is already in the provider: wait for the load before '
        'computing the new list, with final current = state.value ?? '
        'await future. The same guard is harmless in updateNotes and '
        'remove, where the drawer has already forced the load, and it '
        'removes the need for any reader to know which entry point '
        'arrived first.'),
    ...sec('the error path'),
    ...para('//',
        'If decoding fails, build() throws and the provider holds an '
        'error. The drawer shows a red generic message and offers no '
        'way out. What happens to a later save() is a Riverpod detail '
        'worth knowing: in version 2.6, reading value on an error '
        'state rethrows the original error instead of returning null. '
        'I confirmed that with the same replica, fed a corrupt '
        'string: the first line of save() throws a FormatException, '
        'nothing is written, and the exception escapes the button '
        'handler, so the snackbar never appears. The effect is that '
        'unreadable storage is neither overwritten nor repaired, and '
        'a user in that state can never save again until site data is '
        'cleared. The race above is the more dangerous bug because it '
        'fails silently; this one at least fails loudly.'),
    ...sec('how it is used'),
    ...pt('//', 'NarrowTopicView',
        'the Save to notebook button calls save and then shows a '
        'snackbar if the widget is still mounted.'),
    ...pt('//', 'NotebookDrawer',
        'watches the provider with when(loading, error, data), lists '
        'entries newest first, and offers a delete button and a notes '
        'field per entry.'),
    ...pt('//', 'language',
        'the drawer reads the language preference for its labels; the '
        'stored topics keep whatever language they were generated in.'),
    ...sec('testing and limits'),
    ...pt('//', 'no tests',
        'there is no test for this controller. The race above is the '
        'kind of thing a ProviderContainer test with a fake store '
        'catches in a few lines.'),
    ...pt('//', 'whole-list writes',
        'every keystroke in a note rewrites everything.'),
    ...pt('//', 'no export or import',
        'the notebook lives in one browser profile. Clearing site '
        'data erases it, and there is no way to carry it elsewhere.'),
    ...pt('//', 'no size guard',
        'browsers cap localStorage, and nothing handles that failure.'),
    ...pt('//', 'no dedupe',
        'the same topic can be saved more than once.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
