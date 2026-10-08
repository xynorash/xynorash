import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/ingest.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'ingest.rs — the named-pipe front door'),
    cm('//', r'bytes in, frames out, and a session boundary the graph can trust'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'accepts the producer’s pipe connection, decodes frames, routes them'),
    kv('language', r'Rust, tokio named pipes (Windows only)'),
    kv('size', r'80 lines'),
    kv('history', r'7 commits, 2026-07-01 to 2026-07-19'),
    kv('pipe', r'\\.\pipe\heaplens by default, HEAPLENS_PIPE to override'),

    ...sec(r'why this file exists'),
    ...para('//',
        r'The observed program (or the injected hook DLL inside it) runs '
        r'a writer thread that connects to a named pipe and writes '
        r'frames. Something in the daemon has to own the server end of '
        r'that pipe, turn the byte stream back into frames, and hand '
        r'the frames to the graph loop without understanding them. The '
        r'Build Spec scopes this file in one sentence: "This module '
        r'only decodes and routes. It contains no graph logic." The '
        r'80 lines honour that.'),
    blank,
    ...para('//',
        r'It is also the daemon’s only source of truth about whether '
        r'a producer is alive. The pipe closing is the signal; '
        r'everything the rest of the daemon knows about "target '
        r'exited" starts as a Ok(0) from read() in this file.'),

    ...sec(r'the accept loop'),
    ...code('rust', 'crates/heaplens-daemon/src/ingest.rs · run(), creating and connecting a pipe instance', r'''
pub async fn run(pipe_name: String, tx: mpsc::UnboundedSender<GraphMsg>) {
    let mut first = true;
    loop {
        // Create the pipe server. first_pipe_instance only on the first creation.
        let mut server = {
            let mut opts = ServerOptions::new();
            if first {
                opts.first_pipe_instance(true);
            }
            match opts.create(&pipe_name) {
                Ok(s) => {
                    first = false;
                    s
                }
                Err(e) => {
                    warn!("pipe create failed: {e}");
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                    continue;
                }
            }
        };

        info!("waiting for client on {pipe_name}");
        if server.connect().await.is_err() {
            warn!("pipe connect failed, retrying");
            continue;
        }
        info!("client connected");
'''),
    ...para('//',
        r'The shape is the classic one-client-at-a-time named-pipe '
        r'server: create an instance, wait for a client, serve it until '
        r'it goes away, then loop back and create a fresh instance. '
        r'There is never a second instance listening while a client '
        r'is connected, so a second producer cannot connect until the '
        r'first has disconnected. That matches the design the stage 7 '
        r'document assumes: the daemon "already serializes pipe '
        r'connections one at a time" (section 3.4). Nothing here '
        r'tries to serve two targets at once, and nothing in the '
        r'daemon above it could use two.'),
    blank,
    ...para('//',
        r'run() never returns. Its callers treat it as a background '
        r'task: main.rs spawns it, and every integration test that '
        r'uses it ends with ingest_handle.abort().'),

    ...sec(r'first_pipe_instance, and the flag that was cleared too early'),
    ...para('//',
        r'ServerOptions::first_pipe_instance(true) asks Windows to '
        r'fail the create if an instance of that pipe name already '
        r'exists. The code sets it on the first create only (its '
        r'comment: "first_pipe_instance only on the first creation"), '
        r'which turns "the pipe name is already taken" into an error '
        r'instead of a silent second server.'),
    blank,
    ...para('//',
        r'The first version cleared the flag before the create '
        r'attempt, and the fix is a two-line move recorded in '
        r'commit ca21fdc on the day the file was written '
        r'(2026-07-01, the title: "clear first flag only after '
        r'successful pipe create"). My reading of the diff: with the '
        r'flag cleared early, a failed first create (another daemon '
        r'already owns the name) would be followed by a retry with '
        r'the check off, and the second daemon would then happily '
        r'create its own instance of the same pipe name and share '
        r'it, defeating the guard it had just tripped. Now `first = '
        r'false` runs only in the Ok arm, so the guard stays on until '
        r'one create succeeds.'),
    blank,
    ...para('//',
        r'The failure arm sleeps 100 ms and retries rather than '
        r'exiting. A second daemon therefore never shares the first '
        r'one’s pipe while it is alive, and also never gives up: it '
        r'logs "pipe create failed" about ten times a second until '
        r'the first daemon exits or it is killed.'),

    ...sec(r'reading frames out of a byte stream'),
    ...code('rust', 'crates/heaplens-daemon/src/ingest.rs · the read loop', r'''
let mut decoder = FrameDecoder::new();
let mut buf = vec![0u8; 4096];
let mut handshook_pid: Option<u64> = None;

loop {
    match server.read(&mut buf).await {
        Ok(0) => {
            info!("client disconnected");
            if let Some(pid) = handshook_pid {
                let _ = tx.send(GraphMsg::TargetDisconnected { pid });
            }
            break;
        }
        Ok(n) => {
            decoder.push(&buf[..n]);
            for frame in decoder.by_ref() {
                match frame {
                    Frame::Events(events) => {
                        let _ = tx.send(GraphMsg::Events(events));
                    }
                    Frame::Symbols(syms) => {
                        let _ = tx.send(GraphMsg::Symbols(syms));
                    }
                    Frame::Handshake { pid, name } => {
                        handshook_pid = Some(pid);
                        let _ = tx.send(GraphMsg::TargetConnected { pid, name });
                    }
                }
            }
        }
        Err(e) => {
            warn!("pipe read error: {e}");
            if let Some(pid) = handshook_pid {
                let _ = tx.send(GraphMsg::TargetDisconnected { pid });
            }
            break;
        }
    }
}
'''),
    ...para('//',
        r'A pipe is a byte stream. The reader has no idea where a '
        r'frame begins: a read may deliver half a frame, or one and a '
        r'half. All of that is delegated to FrameDecoder in '
        r'heaplens-protocol: push() appends bytes, and iterating the '
        r'decoder yields every complete frame currently buffered. '
        r'Incomplete frames stay buffered; the decoder’s doc says '
        r'"Incomplete frames (not enough bytes yet) return None '
        r'without draining" and "Malformed frames are skipped '
        r'silently (skip-and-continue)". The protocol crate tests '
        r'feeding one byte at a time (frame_partial.rs). So this '
        r'file does not need an error path for garbage, and '
        r'has none.'),
    blank,
    ...para('//',
        r'Numbers show why that matters. The allocator-side writer '
        r'(heaplens-alloc/src/writer.rs) flushes a batch at 64 events '
        r'or every 1 ms. An AllocEvent is 168 bytes, so a full EVENTS '
        r'frame is 4 + 1 + 2 + 64 x 168 = 10,759 bytes on the wire '
        r'(a u32 length, a type byte, a u16 count, then the events). '
        r'The read buffer here is 4096 bytes, so a full batch arrives '
        r'in at least three reads, and the decoder reassembles it. '
        r'The buffer size is not tuned anywhere I could find; it is '
        r'a conventional page-sized chunk.'),

    ...sec(r'the session boundary: handshook_pid'),
    ...para('//',
        r'Three lines carry more design than the rest of the file.'),
    ...pt('//', 'handshook_pid: Option<u64>',
        r'Set when a HANDSHAKE frame arrives. That frame carries the '
        r'producer’s pid and process name (the writer sends it right '
        r'after connecting).'),
    ...pt('//', 'TargetConnected on the handshake',
        r'The graph loop is told that a session started, and for which '
        r'pid, so it can label the stats banner and decide whether an '
        r'Attach request is about an already-observed process '
        r'(msg.rs, should_reset_on_attach).'),
    ...pt('//', 'TargetDisconnected only if a pid is known',
        r'On Ok(0) (clean close) or an Err (read failure), if a '
        r'handshake was seen, the disconnect carries that pid. A '
        r'connection that closes before ever handshaking produces no '
        r'message at all, because there is no pid to attach it to.'),
    blank,
    ...para('//',
        r'The stage 7 design (section 4.4) gives the intent: the '
        r'daemon "uses the now-activated PID ... to mark the session '
        r'as ended (rather than awaiting the next connection) and to '
        r'prompt Flutter to show target process exited rather than '
        r'silently sitting on a stale graph". The word "activated" '
        r'refers to the HANDSHAKE frame’s pid field, which had been '
        r'decoded but unused until then. Ingest.rs used to drop it '
        r'with a comment, "Handshake is informational". The two-'
        r'commit history of that arm is the file’s main evolution: '
        r'0edc728 (2026-07-17) forwarded it for the diagnostics '
        r'banner, 724695a (2026-07-19) reshaped it into the '
        r'pid-carrying pair.'),
    blank,
    ...para('//',
        r'The key property for the rest of the system is that '
        r'disconnect events carry identity. The msg.rs page explains '
        r'the race this protects: an old target’s pipe-close arriving '
        r'after the daemon has already moved on to a new target.'),

    ...sec(r'timeline'),
    ...pt('//', '2026-07-01 (684d480)',
        r'the first version: create, connect, read, decode, and route '
        r'Events; Symbols and Handshake were received and ignored.'),
    ...pt('//', '2026-07-01 (ca21fdc, d8d567b)',
        r'the first-instance flag fix; a clippy pass.'),
    ...pt('//', '2026-07-08 (43fc22e)',
        r'Symbols start being forwarded as GraphMsg::Symbols. Until '
        r'then the daemon had no names at all: the commit says the '
        r'"previously-discarded Frame::Symbols" were "wired into the '
        r'daemon’s resolver". This is one of the four bugs that '
        r'together kept φ from ever producing a real edge.'),
    ...pt('//', '2026-07-17 / 2026-07-19 (0edc728, 724695a)',
        r'Handshake forwarded; then TargetConnected and '
        r'TargetDisconnected { pid }.'),

    ...sec(r'how it is tested'),
    ...para('//',
        r'There is no unit test of run() itself; it needs a real '
        r'Windows named pipe and a client. It is exercised end to end '
        r'by every test that spawns a real producer, all marked '
        r'#![cfg(windows)]:'),
    ...pt('//', 'cross_process_wire.rs',
        r'spawns wire_producer.exe, which connects to the pipe with '
        r'the real writer thread; the test asserts at least 100 allocs '
        r'arrive and that φ sees the expected topology.'),
    ...pt('//', 'cross_process_wire_gui.rs and cross_process_wire_tui.rs',
        r'the same for the two demo targets.'),
    ...pt('//', 'hook_self_load_wire.rs and hook_self_load_spawned_thread.rs',
        r'the same path with the injected hook DLL as the producer.'),
    blank,
    ...para('//',
        r'Note that the file called ingest_loopback.rs does not '
        r'open a pipe at all. "Loopback" there means encoding events '
        r'into bytes, decoding them with FrameDecoder, and driving the '
        r'graph in-process. It tests the decoder half of this file’s '
        r'job on any platform; the pipe half is covered only by the '
        r'cross-process tests.'),

    ...sec(r'limits'),
    ...pt('//', 'Windows only',
        r'The imports (tokio::net::windows::named_pipe) mean this '
        r'module, and so the library crate, only builds on Windows. '
        r'Cargo.toml lists windows-sys unconditionally.'),
    ...pt('//', 'one producer at a time',
        r'By design and by structure. A second producer waits.'),
    ...pt('//', 'the pid is taken on trust',
        r'The handshake pid is whatever the producer wrote. The '
        r'daemon never asks the OS which process owns the other end '
        r'of the pipe, so the identity logic in main.rs and msg.rs '
        r'is only as good as the producer’s honesty. For a local '
        r'developer tool that is a reasonable trade; it would not be '
        r'for a service.'),
    ...pt('//', 'no back-pressure',
        r'send() on an unbounded channel always succeeds, and its '
        r'result is discarded. If the graph loop falls behind, this '
        r'task keeps reading and the queue grows (see the 2026-07-22 '
        r'backlog figures in main.rs and graph.rs). The cost of a '
        r'slow consumer is memory, not a stalled pipe.'),
    ...pt('//', 'no reconnect logic on this side',
        r'None is needed: the producer’s writer reconnects, and the '
        r'daemon’s loop is always ready for the next client. A '
        r'producer that reconnects after a daemon restart starts '
        r'with an empty symbol cache, because writer.rs clears it '
        r'at the top of its reconnect loop.'),
    blank,
    link('→ github.com/XNash/heaplens', 'https://github.com/XNash/heaplens'),
  ],
);
