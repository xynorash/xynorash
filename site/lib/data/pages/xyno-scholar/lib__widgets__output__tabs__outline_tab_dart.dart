import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/widgets/output/tabs/outline_tab.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'outline_tab.dart — a paper in three numbered parts'),
    cm('//', r'the suggested structure, drawn as a column of cards'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv(r'role', r'third tab of a narrow topic: the suggested structure'),
    kv(r'language', r'Dart / Flutter, one stateless widget'),
    kv(r'size', r'71 lines, 1 commit, never edited'),
    kv(r'input', r'a list of OutlinePart (partNumber, title, description)'),
    kv(r'history', r'7a200e7 (2026-08-06 09:41)'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'After a topic and a reading list, the next thing a student '
        r'asks is how to organise the paper. The model is asked for a '
        r'structure of exactly three parts: the refine instruction in '
        r'mistral_client.dart says “3 suggestedStructure parts”, and '
        r'the model class comments the numbers as “I | II | III”. '
        r'This widget draws them. It is the plainest of the four tabs, '
        r'and the one that most clearly shows how the output cards '
        r'are built.'),

    ...sec(r'the data it draws'),
    ...code('dart', r'lib/models/outline_part.dart · lines 1-4', r'''
class OutlinePart {
  final String partNumber; // I | II | III
  final String title;
  final String description;'''),
    ...para('//',
        r'All three fields are strings. The part number is not an '
        r'integer: it is the Roman numeral the model writes, which '
        r'suits a French paper, where parts are numbered I, II, III. '
        r'The widget never parses it. It puts the string in a circle, '
        r'whatever it is. If the model wrote “1”, the circle would '
        r'show a 1.'),

    ...sec(r'the card'),
    ...code('dart', r'lib/widgets/output/tabs/outline_tab.dart · lines 19-30', r'''
        children: parts.map((part) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: ['''),
    ...para('//',
        r'A card is a Container with a raised surface, a 10-pixel '
        r'radius and a one-pixel border, 14 pixels apart from the next. '
        r'Compare it to the bibliography tab: lines 50 to 57 of '
        r'bibliography_tab.dart are the same decoration, down to the '
        r'numbers. The two files each build the card by hand. There is '
        r'a shared SidebarCard in the repo, but for the sidebar, '
        r'and nothing equivalent for the output side. With two users '
        r'the duplication is cheap; a third tab with the same card '
        r'would be the moment to extract it.'),
    blank,
    ...para('//',
        r'The inside is a Row with crossAxisAlignment start. The number '
        r'sits at the left and the text column takes the rest, '
        r'aligned to the top, so a long description grows downward '
        r'without pulling the number to the middle.'),

    ...sec(r'the number badge'),
    ...code('dart', r'lib/widgets/output/tabs/outline_tab.dart · lines 31-47', r'''
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.teal.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    part.partNumber,
                    style: AppTypography.serif(
                      weight: FontWeight.w700,
                      color: colors.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 14),'''),
    ...para('//',
        r'A 36 by 36 circle in a 12-percent teal tint with the numeral '
        r'in bold serif, teal on teal. The size is fixed, which '
        r'works for I, II and III. The widest of those is III, and a '
        r'longer string (a model that answered “Part three”) would '
        r'overflow the circle, because nothing here shrinks the text. '
        r'The prompt makes that unlikely, but it is the one place where '
        r'the layout trusts the model.'),

    ...sec(r'the text column'),
    ...code('dart', r'lib/widgets/output/tabs/outline_tab.dart · lines 48-63', r'''
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        part.title,
                        style: AppTypography.serif(
                          fontSize: 17,
                          color: colors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      MarkdownText(part.description),
                    ],
                  ),
                ),'''),
    ...para('//',
        r'The title is in the serif face at 17 pixels, one point larger '
        r'than a bibliography title, since a part heading is a '
        r'heading and a book title is a line of a list. The '
        r'description goes through MarkdownText, which lists outline '
        r'descriptions explicitly among the prose fields it renders. '
        r'The Expanded gives the column the remaining width, so long '
        r'text wraps. Without it the Row would ask the Text for an '
        r'unbounded width and Flutter would report an overflow.'),

    ...sec(r'edge cases'),
    ...pt('//', r'no parts',
        r'the model class falls back to an empty list when the key is '
        r'missing; the tab then draws an empty column with padding.'),
    ...pt('//', r'more than three',
        r'the widget draws all of them. The count of three is a '
        r'prompt instruction, not a limit in the code.'),
    ...pt('//', r'a part with empty strings',
        r'it renders an empty circle and no heading. Nothing filters '
        r'such a part out.'),
    ...pt('//', r'no state',
        r'there is nothing to dispose; the parts list is read-only.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'No widget test targets it. The structure is parsed in the '
        r'client tests: the mistral_client tests build narrow-topic '
        r'fixtures, so OutlinePart.fromJson is exercised through them. '
        r'The card is checked by eye.'),

    ...sec(r'where it is used'),
    ...para('//',
        r'narrow_topic_view.dart builds a TabBarView of four tabs in '
        r'the order Intersection, Bibliography, Outline, Refine, each '
        r'inside a SingleChildScrollView in a box 620 pixels tall. '
        r'OutlineTab gets only topic.suggestedStructure. It has no '
        r'language argument, because it has no label of its own: '
        r'all of its text comes from the model.'),

    ...sec(r'history'),
    ...pt('//', r'7a200e7, 2026-08-06 09:41',
        r'the scaffold commit. The file has not changed since, across '
        r'the nine commits that swapped three model providers around '
        r'it.'),
  ],
);
