import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/heaplens_flutter/test/fixtures/snapshot.json',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'snapshot.json — a real chain of 101 allocations'),
    cm('//', r'the captured message that pins the wire format for the Dart models'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'captured snapshot message used by the contract test'),
    kv('language', r'JSON'),
    kv('size', r'1215 lines, one commit: 9ac04cd (2026-07-06)'),
    kv('shape', r'type, ts, nodes: 101 entries of 8 fields each'),
    kv('provenance', r'test/fixtures/PROVENANCE.md: real capture, nothing edited'),
    kv('read by', r'test/models/contract_test.dart'),
    ...sec(r'why this file exists'),
    ...para('//',
        r'Before any UI existed I wanted one thing settled: the Dart '
        r'models must read exactly what the daemon really sends. The way to settle that is to '
        r'record a real message and make a test parse it. This is '
        r'that recording, a full snapshot captured from a live '
        r'daemon session, and its sibling diffs. The provenance note '
        r'says it is a real snapshot, captured mid-session with 101 '
        r'live nodes, with no field altered.'),
    ...sec(r'the shape'),
    ...code('json', 'heaplens_flutter/test/fixtures/snapshot.json · lines 1-16', r'''
{
  "type": "snapshot",
  "ts": 329700,
  "nodes": [
    {
      "id": 571,
      "ptr": 1599777467168,
      "size": 256,
      "ts": 230900,
      "symbol": "0x7ff74ba66230",
      "live": true,
      "state": "healthy",
      "edges": [
        572
      ]
    },'''),
    ...para('//',
        r'A snapshot has a type tag, a timestamp of 329700, and a '
        r'list of nodes. Each node has eight fields: id, ptr, size, '
        r'ts, symbol, live, state and edges. The ptr is a 64-bit '
        r'address written as a plain JSON number, 1599777467168 for '
        r'the first node, and that is the detail behind the decision '
        r'to run only on the Dart VM: a number like that is exact in '
        r'a 64-bit integer and would be at risk once an address '
        r'passed 2^53 in JavaScript. The addresses here are far '
        r'below that limit, so the fixture does not exercise it, but '
        r'the shape is the one the decision protects.'),
    ...sec(r'what the data actually is'),
    ...para('//',
        r'Reading the file rather than the plan gives a more '
        r'specific picture than the note does. The 101 nodes form a '
        r'single chain. Every node but the last lists exactly one '
        r'edge, to the node with the next id, so 506 owns 507, which '
        r'owns 508, and on to 606, which owns nothing. The first '
        r'node in the chain, 506, is the only one nobody owns. It is '
        r'also the largest by far, at 2400 bytes, with a timestamp '
        r'of 100, the smallest in the file; the remaining sizes '
        r'alternate between 128 and 256 bytes, fifty of each among '
        r'the children.'),
    ...code('json', 'heaplens_flutter/test/fixtures/snapshot.json · lines 125-136', r'''
    {
      "id": 506,
      "ptr": 1599777439984,
      "size": 2400,
      "ts": 100,
      "symbol": "0x7ff74ba66230",
      "live": true,
      "state": "healthy",
      "edges": [
        507
      ]
    },'''),
    ...para('//',
        r'Every node is live and every node is healthy, so this file '
        r'contains no orphan, no hot node and no freed node, and '
        r'that is why the provenance note admits the orphan fixture '
        r'had to be edited by hand. Every edge points at an id '
        r'present in the list, so there are no dangling references. '
        r'The nodes are not in id order: the first is 571, then 605, '
        r'593, 551, which is the order of the daemon’s internal map, '
        r'not a sort. Timestamps run from 100 to 270900 against a '
        r'snapshot timestamp of 329700, and addresses span about 90 '
        r'kilobytes.'),
    ...para('//',
        r'The symbol of every node is the same string, '
        r'0x7ff74ba66230. That is a hexadecimal address and not a '
        r'resolved function name: the capture target had no symbols, '
        r'so the daemon fell back to the address. All 101 '
        r'allocations come from one call site, which is exactly what '
        r'a synthetic allocation producer does.'),
    ...sec(r'what the test pins'),
    ...para('//',
        r'contract_test.dart parses the file through the same '
        r'GraphMessage factory the live app uses and asserts that '
        r'the result is a GraphSnapshot with timestamp 329700 and '
        r'101 nodes. A second test spot-checks the first node field '
        r'by field: id 571, pointer 1599777467168, size 256, '
        r'timestamp 230900, the hex symbol, live true, state healthy '
        r'and the edge list with the single entry 572. The first '
        r'node is a good choice for the check because it has a '
        r'non-empty edges list, which is the field most likely to be '
        r'mis-parsed. Only that one node is checked in detail; the '
        r'other 100 are only counted.'),
    ...sec(r'limits'),
    ...pt('//', r'one sample',
        r'a single chain of uniform healthy nodes. It cannot catch a '
        r'model bug that only shows with branching trees, multiple '
        r'owners, or other states.'),
    ...pt('//', r'stale risk',
        r'the file is a copy of the wire format at the time of '
        r'capture. If the daemon changes a field, the Dart tests '
        r'keep passing against this JSON until it is captured again.'),
    ...pt('//', r'synthetic traffic',
        r'real wire data, but produced by a test allocator and not '
        r'by an application.'),
    ...pt('//', r'size',
        r'1215 lines for about 21 kilobytes of data, because '
        r'the capture is pretty-printed with one array element per '
        r'line; that makes diffs readable and the file long.'),
    ...sec(r'the end of the file'),
    ...code('json', 'heaplens_flutter/test/fixtures/snapshot.json · lines 1204-1215', r'''
      "id": 528,
      "ptr": 1599777445232,
      "size": 128,
      "ts": 175300,
      "symbol": "0x7ff74ba66230",
      "live": true,
      "state": "healthy",
      "edges": [
        529
      ]
    }
  ]'''),
    ...para('//',
        r'The file ends with the last node, 528, and its single edge '
        r'to 529, and the closing brackets. There is no trailing '
        r'newline in the capture. That is incidental, but a note for '
        r'anyone regenerating it: the parser does not care.'),
    ...sec(r'history'),
    ...pt('//', r'9ac04cd (2026-07-06)',
        r'docs(flutter): M5 build plan and real captured contract '
        r'fixtures. Adds this file with the other three fixtures and '
        r'the provenance note, before any of the UI.'),
  ],
);
