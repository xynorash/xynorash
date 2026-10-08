import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/broad_topics_list.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'broad_topics_list.dart — the menu: five to eight cards and a door to each'),
    cm('//', 'scannable summaries with the field receipt and a Deep Dive button'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'renders the broad-scope response as a vertical list of numbered topic cards'),
    kv('language', 'Dart / Flutter, Riverpod ConsumerWidget'),
    kv('size', '107 lines'),
    kv('history', 'two commits: 7a200e7 (scaffold), 89a9c12 (icon package import)'),
    kv('shows', 'title, whyFitsAllFields (markdown), fieldsCovered chips, Deep Dive'),
    ...sec('what the user is doing here'),
    ...para('//',
        'A broad generation is the question “what could I write '
        'about?” The answer is a menu of five to eight options, and '
        'the student’s task is to scan, compare and choose one. The '
        'list is designed for that task and nothing else. Each card '
        'has the same four parts in the same order, so that the eye '
        'can run down the titles and only stop for detail when '
        'something looks promising.'),

    ...sec('anatomy of a card'),
    ...code('dart', 'lib/widgets/output/broad_topics_list.dart · header row', r'''
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.amber.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}','''),
    ...para('//',
        'The number is computed from the loop index, not read from '
        'the model: the list is built with a collection-for loop '
        'over indices and prints i + 1. Compare the outline tab, '
        'where the numeral is the model’s own string (see '
        'outline_part.dart). The distinction is that these options '
        'are unordered alternatives, so the number is only a handle '
        'for talking about them. The badge is amber, the colour for '
        '“look here”, tinted at 14 per cent.'),
    ...code('dart', 'lib/widgets/output/broad_topics_list.dart · title and rationale', r'''
                    Expanded(
                      child: Text(
                        topics[i].title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),'''),
    ...para('//',
        'The title is plain Text in the serif headline style, '
        'because the prompt declares title fields plain text. The '
        'next element, MarkdownText(topics[i].whyFitsAllFields), is '
        'the model’s argument for why the topic belongs to every '
        'selected field. See broad_topic.dart for why that field '
        'carries that name.'),

    ...sec('the receipt: which fields does it claim?'),
    ...code('dart', 'lib/widgets/output/broad_topics_list.dart · the field chips', r'''
                  children: topics[i].fieldsCovered.map((fieldId) {
                    return Chip(
                      label: Text(
                        fieldLabel(fieldId, prefs.language),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: colors.teal.withValues(alpha: 0.10),
                      side: BorderSide(
                        color: colors.teal.withValues(alpha: 0.3),
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),'''),
    ...para('//',
        'This row is the visible form of the product’s central '
        'promise. Rule 1 of the prompt says every topic must engage '
        'all the selected fields; the chips show which ones the model '
        'says this topic covers, translated back from ids to labels '
        'by fieldLabel (field_catalog.dart). If the user selected '
        'History, Catholic theology and Art history and a card shows '
        'two chips, the gap is on screen. The chip recipe (teal at 10 '
        'per cent, a 30 per cent border, compact density, 12 px '
        'label) is repeated line for line in intersection_tab.dart; '
        'extracting a small FieldChip widget would be the obvious '
        'cleanup. As noted elsewhere, nothing here compares the chips '
        'with the selection automatically.'),

    ...sec('the Deep Dive button'),
    ...code('dart', 'lib/widgets/output/broad_topics_list.dart · Deep Dive', r'''
                  child: TextButton.icon(
                    onPressed: generation.isLoading
                        ? null
                        : () => ref
                              .read(generationProvider.notifier)
                              .deepDive(topics[i]),
                    icon: const Icon(LucideIcons.arrowRight, size: 16),
                    label: Text(s.deepDive),
                  ),'''),
    ...para('//',
        'The button is right-aligned, a text button rather than a '
        'filled one, so that eight cards do not become eight primary '
        'actions competing with the Generate button in the sidebar. '
        'It is disabled while any generation is running (null '
        'onPressed), which prevents a second request being fired '
        'while the first is outstanding. Pressing it hands the whole '
        'BroadTopic to the controller, which reads its title and '
        'keywords: the keywords are never shown on the card. How '
        'that request is formed, and a question about whether it '
        'asks for a narrow topic, is covered on the broad_topic.dart '
        'page.'),
    blank,
    ...para('//',
        'The label is “Approfondir →” or “Deep Dive →”; the arrow is '
        'part of the localised string and the icon is also an arrow, '
        'so the affordance appears twice in the same button.'),

    ...sec('what the list does not do'),
    ...para('//',
        'There is no way to save or copy a broad topic, to remove '
        'one from the list, or to compare two. The only action on a '
        'card is Deep Dive. That fits the intent (a broad result is a '
        'menu and should be disposable) and means the notebook only '
        'ever holds narrow topics. The list also has no empty state '
        'of its own; OutputPanel falls back to the welcome screen '
        'when the broad list is empty.'),

    ...sec('what is tested'),
    ...para('//',
        'The widget has no test. The broad response it renders is '
        'parsed in test/mistral_client_test.dart, which checks one '
        'BroadTopic with title ‘Test Topic’. The number of cards '
        '(five to eight) is a prompt instruction, not something '
        'tested or enforced in Dart: the list renders however many '
        'topics arrive.'),

    ...sec('limits and what is next'),
    ...pt('//', 'duplicated chip recipe',
        'the same Chip configuration appears here and in the '
        'intersection tab.'),
    ...pt('//', 'no compliance check',
        'chips display the model’s claim; a subset test against the '
        'selection could highlight a topic that dropped a field.'),
    ...pt('//', 'long lists',
        'the list is a plain Column inside a scroll view, so all cards '
        'are built at once; with eight that is fine.'),
    ...pt('//', 'deep dive depends on sidebar scope',
        'see broad_topic.dart: the request does not force narrow scope.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
