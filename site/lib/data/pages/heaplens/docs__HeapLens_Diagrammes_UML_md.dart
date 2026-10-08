import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/docs/HeapLens_Diagrammes_UML.md',
  lines: [
    heading('# HeapLens — Modélisation UML complète'),
    blank,
    ...text('Seven diagrams, written in French as Mermaid source, '
        'for Chapter 3 (Conception et Modélisation) of the Master’s '
        'thesis this project belongs to. They are the earliest '
        'picture of the system, committed on day one and never '
        'edited since.'),
    blank,
    kv('role', 'UML model of HeapLens for the thesis, as code'),
    kv('language', 'French prose, Mermaid diagrams, one SVG'),
    kv('size', '407 lines · 7 figures (3.1 to 3.7)'),
    kv('history', 'a single commit, a55f7c1 on 2026-06-24'),
    kv('views covered', 'functional, structural, behavioural x3, architectural x2'),

    ...sec('why diagrams as text'),
    ...text('The document contains no raster images. It contains '
        'Mermaid source, which renders on GitHub, in VS Code and in '
        'Obsidian, and which diffs like any other file. The '
        'integration notes at the bottom tell the author how to '
        'turn that source into figures for the thesis: paste into '
        'mermaid.live, export PNG or SVG, number the figure, add '
        'the caption and the line “Source : Auteur”.'),
    ...text('That choice matters for a project that wrote its '
        'specification before its code. A diagram that lives next '
        'to the Build Spec in the same repository can be reviewed '
        'in the same pull request as the contract it illustrates. '
        'In practice it was not: this file has exactly one commit, '
        'and the architecture has since gained a launcher, an '
        'injector and a hook DLL that no figure shows. The diagrams '
        'are best read as the intended design on day one, and the '
        'sections below mark where the code agrees and where it '
        'moved.'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · the table of figures (trimmed)', r'''
| 1 | Cas d'utilisation | Fonctionnelle | Acteurs et fonctionnalités du système |
| 2 | Classes | Structurelle | Modèle GrapheTas et structures des quatre couches |
| 3 | Séquence | Comportementale | Flux d'un événement d'allocation et non-blocage |
| 4 | États | Comportementale | Cycle de vie d'un nœud d'allocation |
| 5 | Activité | Comportementale | Traitement d'un événement et détection d'anomalies |
| 6 | Composants | Architecturale | Composants déployables et interfaces |
| 7 | Déploiement | Architecturale | Processus déployés sur la machine Windows |'''),
    ...text('The set is a deliberate coverage argument: the '
        'closing note says each diagram corresponds to a standard '
        'UML view, so the model is complete across functional, '
        'structural, behavioural and architectural angles. It is '
        'also a good checklist for anyone documenting a system '
        'with threads and processes, where the sequence and state '
        'views usually say more than the class view.'),

    ...sec('figure 3.1: use cases'),
    ...text('Two actors. The developer starts the daemon, '
        'instruments a program, watches, inspects, filters and '
        'exports. The observed program is a secondary actor: it '
        'does nothing the developer asks, but its events are what '
        'trigger anomaly detection. The only structure is two '
        '“include” links, which say that inspecting a node and '
        'flagging an anomaly are both parts of the live view.'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.1 (trimmed)', r'''
  Dev --> UC1
  Dev --> UC2
  Dev --> UC3
  Prog --> UC5
  UC4 -.->|"include"| UC3
  UC5 -.->|"include"| UC3'''),
    ...text('Reading it against the repository: UC1, instrument a '
        'program, is two lines of Rust (the #[global_allocator] '
        'declaration) and, since 2026-07-28, an environment '
        'variable, HEAPLENS_ENABLE, so that linking the allocator '
        'is not by itself a request to be observed. Instrumenting '
        'is no longer the only route either: the process picker '
        'lets the developer attach to a running program through '
        'the injector. UC7, export a snapshot, is listed in the '
        'build spec’s control bar and was not built; the Flutter '
        'tree contains no export code.'),

    ...sec('figure 3.2: classes and the GrapheTas model'),
    ...text('The class diagram carries the formal heart of the '
        'thesis. The caption gives the idea in one line: the '
        'ownership graph composes nodes, “traduisant directement '
        'le modèle formel GrapheTas = (N, A, φ)”. N is the set of '
        'live allocations, A the ownership edges, φ the inference '
        'function that decides which allocation owns which. The '
        'orphan, the central notion of the thesis, appears as a '
        'method on the node:'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.2, Node', r'''
  class Node {
    +u64 id
    +u64 ptr
    +u64 size
    +String symbol
    +u64 ts
    +bool live
    +u64[] edgesOut
    +isOrphan(tau) bool
  }'''),
    ...text('This is the model as a mathematician would draw it. '
        'The code organises the same ideas differently, for '
        'reasons that come from concurrency rather than from the '
        'model:'),
    ...bullet('Daemon as a class',
        'there is no Daemon type. The five subsystems the diagram '
        'composes into it are modules wired together in main.rs as '
        'tasks and channels: a graph task owns the graph and the '
        'resolver, a store thread owns the SQLite connection, a '
        'server task owns the WebSocket clients. Ownership by '
        'composition became ownership by message passing, which is '
        'what invariant 9 of the Build Spec asks for.'),
    ...bullet('isOrphan(tau)',
        'the predicate is not a method on Node. It is evaluated '
        'in anomaly::sweep, over every live node on every tick, '
        'against the newest producer timestamp rather than the '
        'wall clock. Same definition, different home.'),
    ...bullet('AnomalyDetector with three detectors',
        'orphan and hot are branches of one sweep function; storm '
        'is a separate StormTracker fed per allocation. A growth '
        'detector as drawn (detectGrowth) does not exist: hot is '
        'a fan-out threshold. The Build Spec page covers that '
        'simplification.'),
    ...bullet('u64[8] stack',
        'the event now carries sixteen frames, so the diagram '
        'undercounts. Several fields on Node (owner, state, '
        'had_owner_once) exist in the code and not in the figure.'),
    ...bullet('HeapLensAlloc with a recursionGuard field',
        'the guard is a per-thread slot (TlsAlloc), not a field, '
        'because the flag must be per thread.'),
    blank,
    ...text('The figure draws a single RingBuffer composed into '
        'HeapLensAlloc. In the code the allocator is a unit struct '
        'with no fields; each thread gets its own ring, registered '
        'in a global registry that the writer thread drains. What '
        'the figure does get right is the boundary: the rings stay '
        'inside the observed process and are never shared with the '
        'daemon.'),

    ...sec('figure 3.3: sequence, and the non-blocking promise'),
    ...text('This is the most important diagram in the file, '
        'because it is the picture of the central claim. The '
        'program calls alloc, the wrapper calls the system '
        'allocator, captures a stack and a timestamp, pushes to the '
        'ring and returns the pointer, all before anything '
        'downstream has run:'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.3 (trimmed)', r'''
    P->>A: alloc(layout)
    A->>S: alloc(layout)
    S-->>A: ptr
    A->>A: capture pile + horodatage
    A->>R: push(AllocEvent)
    A-->>P: ptr (retour immediat, sans blocage)

    loop En continu, hors du chemin critique
        T->>R: pop()
        D->>D: resolution des symboles'''),
    ...text('The caption puts it in words: the program gets its '
        'pointer back “avant que toute la chaîne d’observation ne '
        's’exécute”, and the loop labelled “hors du chemin '
        'critique” is the guarantee. Everything inside that loop '
        'happens on other threads or in other processes.'),
    ...text('There is one place the sequence and the code '
        'disagree, and it is a design decision the spec later '
        'made explicit. The figure shows the daemon resolving '
        'symbols (the message “resolution des symboles”, sent from '
        'the daemon to itself). The Build Spec refines this: addresses are '
        'meaningful only inside the observed process, so the '
        'writer thread resolves them there and ships ready-made '
        'address-to-name pairs. The spec calls it a refinement of '
        'requirement R5, and invariant 6 states that the daemon '
        'never symbolizes. The code follows the spec, not the '
        'figure.'),
    ...text('A second, smaller difference: the figure shows the '
        'writer popping events one at a time. The writer drains '
        'all per-thread rings in batches of at most 64 events or '
        'one millisecond. The 64 was in the Build Spec from the '
        'start but did not bind: the drain emptied every ring in '
        'one call, until it overflowed the wire format’s 16-bit '
        'event count under 12-thread load and fa3fe78 gave the '
        'drain an explicit maximum.'),

    ...sec('figure 3.4: the life of a node'),
    ...text('The state diagram names four states in French: '
        'Vivante, Chaude, Orpheline, Libérée (alive, hot, orphan, '
        'freed). The transitions are the thesis in miniature:'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.4 (trimmed)', r'''
    [*] --> Vivante : allocation (addNode)
    Vivante --> Chaude : croissance rapide detectee
    Chaude --> Vivante : croissance stabilisee
    Vivante --> Orpheline : proprietaire libere et age superieur a tau
    Chaude --> Orpheline : proprietaire libere et age superieur a tau
    Orpheline --> Liberee : dealloc (fuite resolue)
    Liberee --> [*] : retrait du graphe (fondu)'''),
    ...text('Orphan is defined as a conjunction: the owner has '
        'been freed and the node is older than τ. That second '
        'half is why the H1 benchmark has to measure from '
        'whichever condition becomes true last. And the diagram '
        'draws the transition from Orpheline to Libérée labelled '
        '“dealloc (fuite resolue)”, which is the only place the '
        'model says what a resolved leak looks like: the orphan '
        'is eventually freed.'),
    ...text('Mapping to the wire format is almost one-to-one. The '
        'protocol’s NodeState enum has four variants, the same '
        'four ideas in English:'),
    ...code('rust', 'crates/heaplens-protocol/src/diff.rs · NodeState', r'''
pub enum NodeState {
    Healthy,
    Orphan,
    Hot,
    Freed,
}'''),
    ...text('Two details are worth knowing. The transition '
        '“Chaude → Vivante” is real, and it is a bug fix. The '
        'first version of the anomaly sweep could only move '
        'nodes into Hot and Orphan, so a cluster that shrank '
        'stayed Hot forever. 338abef (2026-07-06) made the sweep '
        're-evaluate every live node each pass, so Hot heals and '
        'Orphan stays orphan only because its predicate cannot '
        'become false. Second, the daemon never sends Freed. A '
        'freed node leaves through the diff’s remove list, and '
        'the fade the figure calls “fondu” is performed by the '
        'Flutter layout engine; the Freed variant exists in the '
        'enum and in the Dart model, with no producer on the '
        'Rust side.'),

    ...sec('figure 3.5: activity, one event end to end'),
    ...text('The flowchart follows a single AllocEvent. Three '
        'branches by kind, then a common tail: run the heuristics '
        '(orphan, growth, storm), compute the diff, persist, '
        'broadcast. The branch worth reading is deallocation, '
        'because it is where orphans are born:'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.5, Dealloc branch', r'''
    Type -->|"Dealloc"| Find["Trouver le nœud par ptr"]
    Find --> MarkFreed["Marquer le nœud comme libéré"]
    MarkFreed --> HasChildren{"Avait des enfants vivants ?"}
    HasChildren -->|"Oui"| Orphan["Marquer les enfants comme orphelins candidats"]'''),
    ...text('The wording “orphelins candidats” is exact. '
        'The graph does not decide that a leak exists at free time. '
        'It clears the children’s owner, remembers that they had '
        'one, and leaves the verdict to the age check. In '
        'graph.rs that is the loop in on_dealloc setting owner to '
        'None and had_owner_once to true, plus, since the H1 work, '
        'the timestamp of the free.'),
    ...text('The Realloc branch (“Mettre à jour ptr et taille”) '
        'is correct but incomplete. The code has a second path for '
        'a realloc whose old pointer it has never seen, typical '
        'after attaching to a process that already allocated: it '
        'registers the new pointer as a fresh node. The Stage 7 '
        'design records this as an intentional asymmetry with '
        'dealloc, where an unknown pointer is simply dropped.'),

    ...sec('figures 3.6 and 3.7: components and deployment'),
    ...text('The two architectural views say one thing twice: '
        'there are three processes, and the arrows between them '
        'are the only coupling.'),
    ...code('markdown', 'docs/HeapLens_Diagrammes_UML.md · Figure 3.6, the interfaces', r'''
    TW -->|"Named Pipe : trames binaires"| NPS
    WS -->|"WebSocket : diffs JSON"| WC
    TS -->|"rusqlite"| DB'''),
    ...text('Binary frames on a named pipe from the observed '
        'process to the daemon, JSON diffs over a loopback '
        'WebSocket from the daemon to the interface, and rows '
        'into SQLite on the side. The deployment caption makes the '
        'consequence explicit: “L’isolation en trois processus '
        'distincts garantit que l’observation reste transparente '
        'pour le programme surveillé”. The figure is provided '
        'twice, as Mermaid and as an SVG with its colours inlined, '
        'and the integration notes say the SVG can be opened in a '
        'browser and exported or inserted as is.'),
    ...text('What the figures do not show is everything that came '
        'later. Today a deployment drawing would add:'),
    ...bullet('a launcher process',
        'HeapLens.exe starts the daemon, waits for its WebSocket '
        'port, starts the UI, and ties the daemon to a Windows Job '
        'Object so it dies with the launcher.'),
    ...bullet('a second way into the observed process',
        'heaplens-hook, a DLL loaded into a running target by '
        'heaplens-injector, a short-lived child process spawned '
        'by the daemon. The pipe and the frame protocol are the '
        'same, which is why the original component diagram '
        'survived the addition.'),
    ...bullet('a control channel',
        'the same WebSocket now also carries requests from the UI '
        '(list processes, attach, detach) and replies.'),
    blank,
    ...text('That the original seams absorbed all three without '
        'redrawing the old figure is the best evidence the model '
        'was drawn at the right level. The pipe and WebSocket '
        'boundaries were load-bearing from the first commit.'),

    ...sec('what holds up and what to take from it'),
    ...bullet('model at the level that survives',
        'class names rotted (there is no Daemon type) but the '
        'relationships did not: allocator to ring, ring to '
        'writer, writer to pipe, pipe to graph, graph to diff.'),
    ...bullet('the sequence diagram is the specification of a '
        'guarantee',
        'one picture states what must be fast and what may be '
        'slow. Several later design questions, from lock-free '
        'rings to try_lock in the capture path, are answers to '
        '“does this stay outside the loop?”.'),
    ...bullet('state diagrams catch missing transitions',
        'the figure draws Chaude back to Vivante from day one, and '
        'the first sweep lacked it until 338abef, whose message '
        'says the fix matches “the locked Q4 sweep design”.'),
    ...bullet('diagrams as code get edited less than prose',
        'one commit in a repo with 136 is the real lesson. If the '
        'figures are to stay true, they need an owner and a '
        'review step, like the contract tests do.'),

    ...sec('limits'),
    ...text('This page compares the figures with the repository '
        'as it stands; it does not compare the figures with the '
        'thesis text, which is not in the repo. The thesis '
        'language is French and so are the quoted captions. '
        'Translations in this page are paraphrases kept close to '
        'the original; the Mermaid in the excerpts is verbatim.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
