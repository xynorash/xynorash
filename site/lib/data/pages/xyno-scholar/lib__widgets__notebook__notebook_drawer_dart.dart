import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/notebook/notebook_drawer.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'notebook_drawer.dart — the shelf: saved topics and your own margin notes'),
    cm('//', 'an end drawer driven by an AsyncNotifier'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'slide-in panel listing saved narrow topics, each with an editable notes field'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget and ConsumerStatefulWidget'),
    kv('size', '159 lines; NotebookDrawer plus a private _NotebookEntryCard'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('state', 'notebookProvider (AsyncNotifier) and preferenceBlockProvider for the language'),
    ...sec('why it exists'),
    ...para('//',
        'A generated topic is gone the moment the student generates '
        'again, and the model will not return the same one twice. '
        'The notebook is the app’s memory. The drawer is its only '
        'view: a place to see what was saved, remove it, and write '
        'the student’s own notes beside it. It deliberately shows '
        'little. Only the title, the pitch and a notes field appear; '
        'the bibliography, the outline and the problématique stay in '
        'the saved object (see notebook_entry.dart) but are not '
        'rendered here.'),

    ...sec('the three states of a saved list'),
    ...code('dart', 'lib/widgets/notebook/notebook_drawer.dart · the async branches', r'''
              child: notebookAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    s.genericError,
                    style: TextStyle(color: colors.rose),
                  ),
                ),
                data: (entries) {
                  if (entries.isEmpty) {'''),
    ...para('//',
        'notebookProvider is an AsyncNotifier because its first '
        'value must be read from storage, and AsyncValue.when is '
        'how Riverpod forces the UI to say what it does while '
        'loading, on failure and on success. The loading branch is a '
        'spinner. The empty data branch shows the “No topics saved '
        'yet” string. The error branch prints the generic localised '
        'error in rose and discards the exception e, so the reader '
        'learns that something failed but not what. Combined with '
        'NotebookEntry.fromJson throwing on a missing topic, one '
        'corrupt entry would put the whole drawer in that state '
        '(see notebook_entry.dart).'),
    ...para('//',
        'The drawer is 440 px wide, on the surface cream rather than '
        'the page parchment, with a header row (book icon, title in '
        'the serif headline style, close button) and a divider. '
        'It lives in HomeScreen as endDrawer and is opened by the '
        'bookMarked icon in the app bar; the close button just pops '
        'the navigator.'),

    ...sec('each entry is its own small stateful widget'),
    ...code('dart', 'lib/widgets/notebook/notebook_drawer.dart · the entry card state', r'''
class _NotebookEntryCardState extends ConsumerState<_NotebookEntryCard> {
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.entry.personalNotes);
  }'''),
    ...para('//',
        'The card is stateful for one reason: the notes field needs '
        'a TextEditingController, and a controller must outlive '
        'rebuilds. It is created in initState with the stored '
        'notes as its initial text, and disposed in dispose. '
        'Typing does not need to read the controller back; it '
        'reports each change to the provider:'),
    ...code('dart', 'lib/widgets/notebook/notebook_drawer.dart · notes', r'''
            onChanged: (value) => ref
                .read(notebookProvider.notifier)
                .updateNotes(widget.entry.id, value),'''),
    ...para('//',
        'This is write-through persistence with no save button: '
        'every keystroke produces a new NotebookEntry, a new list '
        'and a full re-serialisation of the notebook into '
        'shared_preferences (see notebook_provider.dart). There '
        'is no debounce and no “saved” indicator. For a notebook of '
        'a few entries the cost is negligible, and the benefit is '
        'that closing the drawer, or the tab, never loses text. The '
        'controller keeps showing what the user typed because it is '
        'initialised once; rebuilds caused by the provider update '
        'do not reset it.'),

    ...sec('a suspicion about deleting from the middle'),
    ...para('//',
        'Here is something I noticed on reading, which I have '
        'not reproduced. The list is built like this:'),
    ...code('dart', 'lib/widgets/notebook/notebook_drawer.dart · the list', r'''
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) =>
                        _NotebookEntryCard(entry: entries[index], strings: s),
                  );'''),
    ...para('//',
        'The cards have no key. Flutter matches the State of a '
        'child to a position in the list when widgets have '
        'the same type and no key. If the first of three entries is '
        'removed, the widget at position 0 is updated with the '
        'second entry, but its State, and therefore its '
        '_notesController, is the one that belonged to the first. '
        'The controller is only read in initState and there is no '
        'didUpdateWidget. So the card for the second entry would '
        'show the first entry’s notes text while its title and '
        'pitch are correct, and typing there would save into the '
        'second entry’s id. The standard fix is a ValueKey on '
        'entry.id. This reading follows from how Flutter reuses '
        'State and from the absence of keys in the code; treat it '
        'as a probable bug until it has been run.'),
    ...para('//',
        'The remove action itself is a rose trash icon with a '
        'localised “Remove” tooltip and no confirmation. Saving '
        'gets a snack bar (“Saved to notebook”); deleting does '
        'not get an undo. The asymmetry is a design choice in '
        'the sense that the code is consistent about it: '
        'creating is acknowledged, destroying is immediate.'),

    ...sec('what is shown, and why that is enough'),
    ...para('//',
        'Each card shows the title in the serif face at 16 px, the '
        'pitch through MarkdownText, and the notes field with three '
        'lines. The pitch, not the problématique, is the summary; '
        'the code does not say why, and my guess is that the pitch '
        'is written as an introduction and so reads on its own. '
        'Keeping the card small should leave the drawer scannable '
        'with a dozen entries. The cost is that '
        'to see the outline or the sources of a saved topic, there is '
        'no way to open it again: the drawer has no “open” action '
        'that would put the entry back into the main view. Saved '
        'topics are readable only in summary form.'),

    ...sec('what is tested'),
    ...para('//',
        'Nothing in test/ opens the drawer, saves an entry or '
        'touches the notebook provider.'),

    ...sec('limits and what is next'),
    ...pt('//', 'missing keys',
        'a ValueKey(entry.id) on each card would remove the state '
        'reuse risk described above.'),
    ...pt('//', 'no way to reopen a topic',
        'the saved object contains the full bibliography and '
        'outline, but the drawer cannot show them.'),
    ...pt('//', 'no undo',
        'removal is immediate and permanent.'),
    ...pt('//', 'opaque errors',
        'the error branch hides the exception; one malformed entry '
        'hides the whole notebook.'),
    ...pt('//', 'a write per keystroke',
        'a short debounce would cut the serialisation work without '
        'changing behaviour.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
