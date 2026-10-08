import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'xyno-scholar/lib/models/broad_topic.dart',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', 'broad_topic.dart — one card in the menu of ideas'),
    cm('//', 'five fields, and a keyword list whose only reader is the next request'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', 'one entry of the 5 to 8 options a broad generation returns'),
    kv('language', 'Dart'),
    kv('size', '37 lines'),
    kv('history', 'one commit, 7a200e7 (2026-08-06); unchanged since'),
    kv('fields', 'id, title, whyFitsAllFields, fieldsCovered, keyKeywords'),
    ...sec('why this file exists'),
    ...para('//',
        'Xyno Scholar has two modes. In narrow mode it produces one '
        'finished topic (NarrowTopic). In broad mode, the default, it '
        'produces a menu: five to eight short options the student '
        'can scan, reject, or pick one to deepen. BroadTopic is one '
        'item of that menu. It is deliberately small, because the '
        'whole point of a menu item is that it is cheap to read: a '
        'title, a reason it belongs, the disciplines it touches, and '
        'a few keywords.'),
    ...code('dart', 'lib/models/broad_topic.dart · the fields', r'''
class BroadTopic {
  final String id;
  final String title;
  final String whyFitsAllFields;
  final List<String> fieldsCovered;
  final List<String> keyKeywords;'''),

    ...sec('a field name that is also an instruction'),
    ...para('//',
        'Look at the third name: whyFitsAllFields. It is not '
        '“description” or “summary”. It is a question the model must '
        'answer for every topic: why does this fit all of the '
        'selected fields? The product’s hardest promise is rule 1 of '
        'the system prompt, “EVERY proposed subject must genuinely '
        'engage ALL of these fields”, and a language model asked for '
        'a generic summary will write one that is fluent and '
        'quietly drifts toward the easiest field. Naming the slot '
        'whyFitsAllFields turns the schema itself into a second '
        'statement of the rule at the exact place the model writes '
        'prose. That is my reading of the design, not something the '
        'repository states; what the code does show is that this '
        'exact name is the key the model must fill in the prompt’s '
        'JSON schema, and the Dart class repeats it verbatim.'),

    ...sec('what the UI does with each field'),
    ...pt('//', 'title',
        'plain text, in the serif headline style, next to a '
        'numbered amber circle. The number is the list position plus '
        'one, computed in the widget, not a field of the model.'),
    ...pt('//', 'whyFitsAllFields',
        'rendered through the shared markdown widget, so the model '
        'may use bold, italics and short lists.'),
    ...pt('//', 'fieldsCovered',
        'one teal chip per id, labelled through fieldLabel() (see '
        'field_catalog.dart). This is the on-screen receipt for '
        'rule 1: the chips show which disciplines the model says '
        'it engaged.'),
    ...pt('//', 'keyKeywords',
        'never displayed. Its only reader is the Deep Dive button.'),
    ...pt('//', 'id',
        'parsed and ignored; the list uses position, not id, '
        'for numbering.'),

    ...sec('keyKeywords: output of one call, input of the next'),
    ...para('//',
        'A search for keyKeywords across lib/ finds this class (field, '
        'parser, serializer) and exactly one reader outside it. It is '
        'this:'),
    ...code('dart', 'lib/providers/generation_provider.dart · deepDive', r'''
  Future<void> deepDive(BroadTopic topic) async {
    final apiKey = ref.read(apiKeyProvider).key;
    final prefs = ref.read(preferenceBlockProvider);
    final client = ref.read(mistralClientProvider);
    await _run(
      () => client.generate(
        apiKey: apiKey!,
        prefs: prefs.copyWith(),
        freeText: topic.keyKeywords.join(', '),
        deepDiveOnTitle: topic.title,
      ),
    );
  }'''),
    ...para('//',
        'When the user presses “Deep Dive →” on a card, the card’s '
        'keywords become the free-text focus of a new generate '
        'call and its title becomes deepDiveOnTitle. So the model '
        'is asked to produce the keywords as a way to hand context '
        'forward: the first answer decides what the second '
        'question looks like, and the user never types anything. '
        'That is a neat use of a field that costs a line in the '
        'schema and nothing in the UI.'),
    blank,
    ...para('//',
        'There is a detail in this method worth noticing. The '
        'preferences are passed as prefs.copyWith(), a copy with '
        'nothing changed, and the instruction line in the user turn '
        'depends on prefs.scope: ‘Generate ONE narrow, deep-dive '
        'topic’ for narrow, ‘Generate 5 to 8 broad topic options’ '
        'for broad. As written, nothing in deepDive sets the scope '
        'to narrow. Reading the code, a Deep Dive pressed while the '
        'sidebar still says Broad would send deepDiveOnTitle and the '
        'keywords together with the broad instruction. I have not '
        'run it, and the system prompt does not define '
        'deepDiveOnTitle at all, so what the model does with that '
        'key is up to the model; no test covers deepDive.'),

    ...sec('fromJson and the one method nobody calls'),
    ...code('dart', 'lib/models/broad_topic.dart · fromJson', r'''
  factory BroadTopic.fromJson(Map<String, dynamic> json) {
    return BroadTopic(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      whyFitsAllFields: json['whyFitsAllFields']?.toString() ?? '',
      fieldsCovered:
          (json['fieldsCovered'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      keyKeywords:
          (json['keyKeywords'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }'''),
    ...para('//',
        'The list fields use e.toString() on every element, so a '
        'model that returns a number or an object inside a list '
        'does not crash the parse. This is the lenient half of the '
        'contract described in generation_response.dart. The '
        'class also defines toJson, and nothing calls it: broad '
        'topics are never persisted (only a NarrowTopic can be saved '
        'to the notebook) and are never sent back to the model. '
        'It is symmetrical with NarrowTopic.toJson, and dead.'),

    ...sec('what is not checked'),
    ...para('//',
        'The chips display what the model claims. Nothing compares '
        'a topic’s fieldsCovered with the user’s selection. If the '
        'model drops one of the three selected disciplines for a '
        'topic, the card simply shows two chips; the app does not '
        'filter it out, flag it, or retry. That is a transparent '
        'design, since a reader can see the gap, and also an '
        'unautomated one. An audit of rule 1 is a three-line '
        'set comparison that the repository does not do.'),

    ...sec('limits and what is next'),
    ...pt('//', 'rule 1 is not verified',
        'a subset check of each topic’s fieldsCovered against '
        'the selection could mark non-compliant cards.'),
    ...pt('//', 'deep dive and scope',
        'passing scope: Scope.narrow explicitly in deepDive would '
        'make the button do what its label says.'),
    ...pt('//', 'dead toJson, unused id',
        'both are carried for symmetry and used by nothing.'),
    ...pt('//', 'no test of the Deep Dive path',
        'the client tests cover generate and refine but not '
        'deepDiveOnTitle.'),
    blank,
    link('→ github.com/XNash/xyno-scholar', 'https://github.com/XNash/xyno-scholar'),
  ],
);
