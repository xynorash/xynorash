import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/tabs/refine_tab.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'refine_tab.dart — tell the topic what to change'),
    cm('//', r'four ready-made nudges and a box for your own'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'fourth tab of a narrow topic: ask the model to revise it'),
    kv(r'language', r'Dart / Flutter, a ConsumerStatefulWidget with Riverpod'),
    kv(r'size', r'110 lines, 4 commits'),
    kv(r'calls', r'generationProvider.notifier.refine(topic, instruction)'),
    kv(r'history', r'7a200e7, 89a9c12, c1b3d71, ebafa0f (all 2026-08-06)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'A first answer is rarely the right one. The app does not ask '
        r'you to start over: once you open a topic in depth, this tab '
        r'lets you say what is off (the period, the sources, the angle) '
        r'and sends the current topic back to the model with your '
        r'instruction. The client side of that is refine() in '
        r'mistral_client.dart, which tells the model to “return the '
        r'FULL updated narrowTopic object again” with an added '
        r'refinementSummary that says what changed. This file is the '
        r'form that drives it.'),

    ...sec(r'the presets'),
    ...code('dart', r'lib/widgets/output/tabs/refine_tab.dart · lines 9-21', r'''
const _presetsFr = [
  'Décale la période vers le XVIIIe siècle',
  'Plus de sources primaires',
  'Un angle plus ludique',
  'Réduis la portée géographique',
];

const _presetsEn = [
  'Shift the period to the 18th century',
  'More primary sources',
  'A more playful angle',
  'Narrow the geographic scope',
];'''),
    ...para('//',
        r'Four one-click requests in each language. They are written '
        r'as instructions, in the imperative, because they are sent '
        r'verbatim as the refinementRequest. Each one is a different '
        r'axis of change: time, sources, tone and scope. They map onto '
        r'the sidebar’s own settings (tone has a playful option, the '
        r'scope has a narrow one), but here they act on a single topic '
        r'and do not touch the stored preferences. The first one '
        r'is the same sentence the client test uses: '
        r'“Shift the period to the 18th century”.'),
    blank,
    ...para('//',
        r'The lists are constants and are the same for every topic. A '
        r'topic set in the 12th century gets the same “shift to the '
        r'18th” as one set in the 17th. They are examples of the '
        r'kind of thing to ask, not suggestions computed from the '
        r'topic, and the language choice is only fr against '
        r'everything else (widget.language == fr picks French, any '
        r'other value picks English).'),

    ...sec(r'the state'),
    ...code('dart', r'lib/widgets/output/tabs/refine_tab.dart · lines 33-47', r'''
class _RefineTabState extends ConsumerState<RefineTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String instruction) {
    if (instruction.trim().isEmpty) return;
    ref
        .read(generationProvider.notifier)
        .refine(widget.topic, instruction.trim());
  }'''),
    ...para('//',
        r'The only state is a TextEditingController, created in the field '
        r'initializer and disposed in dispose(), the pattern Flutter '
        r'asks for. _submit is the single exit: it trims, refuses an '
        r'empty instruction, and hands the topic and the text to the '
        r'provider. The preset chips and the button share it, so '
        r'there is one rule for what a valid request is. The Future that '
        r'refine returns is not awaited. Loading and errors are '
        r'reported through the provider’s state, which the widget '
        r'watches.'),

    ...sec(r'the form'),
    ...code('dart', r'lib/widgets/output/tabs/refine_tab.dart · lines 51-78', r'''
    final colors = context.colors;
    final s = AppStrings(widget.language);
    final generation = ref.watch(generationProvider);
    final presets = widget.language == 'fr' ? _presetsFr : _presetsEn;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              return ActionChip(
                label: Text(preset, style: const TextStyle(fontSize: 12)),
                onPressed: generation.isLoading ? null : () => _submit(preset),
                backgroundColor: colors.teal.withValues(alpha: 0.08),
                side: BorderSide(color: colors.teal.withValues(alpha: 0.3)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: InputDecoration(hintText: s.refinePlaceholder),
          ),'''),
    ...para('//',
        r'The widget watches generationProvider as a whole, so any '
        r'change in the global generation state rebuilds this tab. '
        r'What it reads is isLoading. While a request is in '
        r'flight, onPressed is null on every chip, and Flutter greys a '
        r'chip whose handler is null. This is the guard against a '
        r'second request: with the first one running, the user cannot '
        r'queue another. A preset chip is a one-click action: there '
        r'is no confirmation and no preview of what will be sent.'),

    ...sec(r'the button'),
    ...code('dart', r'lib/widgets/output/tabs/refine_tab.dart · lines 80-105', r'''
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: generation.isLoading
                  ? null
                  : () {
                      _submit(_controller.text);
                      _controller.clear();
                    },
              icon: generation.isLoading && generation.isRefining
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.amberOn,
                      ),
                    )
                  : const Icon(LucideIcons.wand2, size: 16),
              label: Text(
                generation.isLoading && generation.isRefining
                    ? s.generating
                    : s.refineButton,
              ),
            ),
          ),'''),
    ...para('//',
        r'The button has two looks. Idle: a wand icon and “Refine '
        r'topic” (Affiner le sujet). Busy: a small spinner and the '
        r'generating label. The test is isLoading && isRefining, not '
        r'isLoading alone, which matters because the same '
        r'provider also runs the first generation and deep dives. '
        r'If the user starts a different request elsewhere, the '
        r'button is disabled (isLoading) but does not claim to be '
        r'refining. The flag exists for this purpose: the provider sets '
        r'isRefining true in refine() and false in all four exit '
        r'paths.'),
    blank,
    ...para('//',
        r'One thing to watch: the click handler calls _submit and then '
        r'_controller.clear() unconditionally. The clear happens even '
        r'if _submit refused. For an empty box that is harmless. If '
        r'the user has no API key, the provider’s refine() returns '
        r'quietly at its first check, and the text the user typed '
        r'is gone with nothing sent. The unlock screen makes that '
        r'state unlikely, since the tab only exists after a topic '
        r'was generated with a key; I note it as a small hole, not '
        r'a likely failure.'),

    ...sec(r'what happens after the call'),
    ...para('//',
        r'The provider sets isLoading and isRefining, awaits the '
        r'client, and replaces the stored response with a narrow-scope '
        r'one that holds the updated topic. It keeps the earlier '
        r'language and fieldsCovered. The new topic arrives with its '
        r'refinementSummary, and narrow_topic_view.dart shows that '
        r'summary above the tabs when it is not empty. So the '
        r'result of pressing the button is not visible in this tab at '
        r'all: the tab’s neighbours change under it. There is no undo; '
        r'the previous version of the topic is replaced in the '
        r'current response.'),

    ...sec(r'history: a progress label that came and went'),
    ...para('//',
        r'Three of the file’s four commits are tied to the model '
        r'provider, and they show the label on the busy button '
        r'changing.'),
    ...pt('//', r'7a200e7, 09:41',
        r'the scaffold, with a plain button label.'),
    ...pt('//', r'89a9c12, 09:58',
        r'only the import: lucide_icons became lucide_icons_flutter '
        r'to fix the web build.'),
    ...pt('//', r'c1b3d71, 10:28',
        r'“Switch Cerebras integration to zai-glm-4.7 with '
        r'streaming”. The label becomes a live counter: s.connecting '
        r'before the first byte, then s.receiving(streamedChars) as '
        r'text arrives.'),
    ...pt('//', r'ebafa0f, 10:52',
        r'“Replace Cerebras integration with Google Gemini”. The '
        r'counter is gone and the label is the static s.generating '
        r'again. The streaming code was removed with the provider.'),
    blank,
    ...para('//',
        r'The refine call has since moved to Mistral (98e7e48 and '
        r'b3d2b1c, 12:19 and 12:54), and the file was not touched '
        r'for that. The widget only knows the provider’s interface, '
        r'so switching the model behind it did not need a '
        r'UI change. That is the design working.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No widget test touches this tab. The behaviour that is '
        r'tested is the client call it drives: '
        r'test/mistral_client_test.dart has a test named '
        r'“refine() returns the updated topic with a '
        r'refinementSummary”, which feeds a fixture through '
        r'refine() with the instruction “Shift the period to the 18th '
        r'century” and checks the summary. The disabled-while-loading '
        r'behaviour and the button states are not covered.'),
  ],
);
