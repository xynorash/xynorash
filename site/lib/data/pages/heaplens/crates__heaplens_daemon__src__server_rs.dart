import '../../../models/project.dart';
import '../../authoring.dart';

final Buffer page = makePage(
  'heaplens/crates/heaplens-daemon/src/server.rs',
  lines: [
    cm('//', '──────────────────────────────────────────'),
    cm('//', r'server.rs — the WebSocket edge of the daemon'),
    cm('//', r'one task per client, a snapshot first, diffs and pushes after, and control requests answered on the same socket'),
    cm('//', '──────────────────────────────────────────'),
    blank,
    kv('role', r'accept WebSocket clients and bridge each to the graph task'),
    kv('language', r'Rust (tokio, tokio-tungstenite)'),
    kv('size', r'214 lines, four commits: 9174573 (2026-07-02) birth, 93bd810 and cffa431 same-day cleanups, 724695a (2026-07-19) control protocol'),
    kv('public API', r'run(addr, connect_tx, target_tx, control_push_tx)'),
    kv('talks to', r'the graph task in main.rs, through three channels'),
    kv('tested by', r'ws_tests.rs, cross_process_wire.rs, target_diagnostics_stats.rs'),
    ...sec(r'why it exists'),
    ...para('//',
        r'The daemon has one consumer-facing surface: a WebSocket on a local port (config.rs defaults it to 127.0.0.1:9999, overridable with HEAPLENS_WS_ADDR). The Flutter GUI and the TUI both connect to it. This file is that surface. It owns no graph state. Everything it knows comes through channels from main.rs’s graph task, which is the single owner of the OwnershipGraph. The graph task is the only place the graph is mutated, which makes server.rs a small adapter: bytes in, channel messages out; channel messages in, JSON text frames out.'),
    blank,
    ...sec(r'the three channels'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 12-25', r'''
/// Run the WebSocket server until the process exits.
///
/// `addr`       — bind address, e.g. `"127.0.0.1:9001"`.
/// `connect_tx` — channel to request a snapshot + diff subscription from the
///                graph task for each new client.
/// `target_tx`  — channel to forward inbound control requests (§3, Stage 7
///                Step 3) to the graph task, which owns both graph state and
///                "which pid is currently attached" session state.
pub async fn run(
    addr: String,
    connect_tx: mpsc::UnboundedSender<ConnectRequest>,
    target_tx: mpsc::UnboundedSender<TargetCmd>,
    control_push_tx: broadcast::Sender<Arc<ControlResponse>>,
) {'''),
    ...pt('//', r'connect_tx',
        r'a client that has just finished its WebSocket handshake sends a ConnectRequest carrying a oneshot reply sender. The graph task answers with the current snapshot and a broadcast::Receiver of diffs.'),
    ...pt('//', r'target_tx',
        r'control requests (list processes, attach, detach) travel to the graph task as TargetCmd values, because that task also owns the "which pid is attached" state and can reset the graph on a target switch.'),
    ...pt('//', r'control_push_tx',
        r'a broadcast::Sender of ControlResponse, used for unprompted notifications; main.rs uses it to send TargetExited when the target’s pipe closes. Each client subscribes when it is accepted.'),
    ...para('//',
        r'The history shows these arriving in order: the first version of the file (9174573, 110 lines) took only connect_tx. 724695a added target_tx and control_push_tx and rewrote the client loop.'),
    blank,
    ...sec(r'the accept loop'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 26-52', r'''
    let listener = match TcpListener::bind(&addr).await {
        Ok(l) => l,
        Err(e) => {
            warn!("WS server bind failed on {addr}: {e}");
            return;
        }
    };
    let bound = listener.local_addr().map(|a| a.to_string()).unwrap_or_else(|_| addr.clone());
    info!("WebSocket server listening on {bound}");

    loop {
        match listener.accept().await {
            Ok((stream, peer)) => {
                info!("WS client connecting from {peer}");
                let tx = connect_tx.clone();
                let ttx = target_tx.clone();
                let push_rx = control_push_tx.subscribe();
                tokio::spawn(async move {
                    handle_client(stream, peer, tx, ttx, push_rx).await;
                });
            }
            Err(e) => {
                warn!("WS accept error: {e}");
            }
        }
    }
}'''),
    ...para('//',
        r'If bind fails the function logs a warning and returns; the process carries on, with no WebSocket and no way to say so to a UI, since there is none yet. After binding, the listener’s local_addr is logged. That line is the product of a commit, 93bd810, which replaced a nested unwrap with map and unwrap_or_else(|_| addr.clone()), so the one place a bad address could panic was removed. A failed accept only logs and loops. Each accepted stream is handed to tokio::spawn with its own clones of the two senders and a fresh push receiver. Note that subscribe happens in the accept loop, before the spawned task starts, so pushes sent between accept and the task’s first poll are not lost.'),
    blank,
    ...sec(r'the handshake and the snapshot'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 61-97', r'''
    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            warn!("WS handshake failed for {peer}: {e}");
            return;
        }
    };

    // Request snapshot + diff subscription from the graph task atomically.
    let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
    if connect_tx.send(ConnectRequest { reply: reply_tx }).is_err() {
        warn!("graph task gone, dropping WS client {peer}");
        return;
    }
    let (snapshot, mut diff_rx): (GraphMessage, broadcast::Receiver<Arc<GraphMessage>>) =
        match reply_rx.await {
            Ok(pair) => pair,
            Err(_) => {
                warn!("graph task dropped reply for {peer}");
                return;
            }
        };

    let (mut ws_sink, mut ws_source) = ws_stream.split();

    // Send the initial full snapshot.
    match serde_json::to_string(&snapshot) {
        Ok(json) => {
            if ws_sink.send(Message::Text(json)).await.is_err() {
                return;
            }
        }
        Err(e) => {
            warn!("snapshot serialize failed for {peer}: {e}");
            return;
        }
    }'''),
    ...para('//',
        r'The order here is the contract the tests check:'),
    blank,
    ...para('//',
        r'1. accept_async completes the WebSocket upgrade, or the task logs and ends. 2. The task asks the graph task for a snapshot and a diff subscription "atomically". main.rs’s side, quoting its comment, subscribes to the broadcast before taking the snapshot with no await between them, so no diff can fall in the gap. A client therefore sees either the data in the snapshot or the diff that follows it, never neither. 3. The snapshot is serialised and sent as the first text frame. If any step fails the client is dropped with a warning, there is no retry.'),
    blank,
    ...para('//',
        r'If the graph task is gone, either the send on connect_tx fails or the reply oneshot is dropped, and each case has its own warning line.'),
    blank,
    ...sec(r'the select loop'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 99-123', r'''
    // Forward diffs as they arrive, and handle inbound control requests
    // (Stage 7 §3) on the same connection.
    loop {
        tokio::select! {
            diff = diff_rx.recv() => {
                match diff {
                    Ok(diff) => match serde_json::to_string(diff.as_ref()) {
                        Ok(json) => {
                            if ws_sink.send(Message::Text(json)).await.is_err() {
                                info!("WS client {peer} disconnected");
                                break;
                            }
                        }
                        Err(e) => warn!("diff serialize failed for {peer}: {e}"),
                    },
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        warn!("WS client {peer} lagged by {n} diffs — some dropped");
                        // Continue: keep the connection alive, just note the gap.
                    }
                    Err(broadcast::error::RecvError::Closed) => {
                        info!("broadcast channel closed, dropping WS client {peer}");
                        break;
                    }
                }
            }'''),
    ...para('//',
        r'One tokio::select! waits on three things for the whole life of the connection: the diff broadcast, the client’s inbound messages, and the control-push broadcast. The diff arm serialises each GraphMessage::Diff and sends it as a text frame. A failed send means the client has gone, so the loop breaks. The interesting arm is Lagged. A broadcast channel with capacity 64 (it is created in main.rs) drops the oldest items for a receiver that falls behind, and tokio reports that as Lagged(n). The server logs it and continues, with the comment "keep the connection alive, just note the gap". That is a trade-off in the open: the client keeps a valid connection but may now be missing diffs, and nothing in the protocol tells it so or forces a resync. A slow client can silently drift from the daemon’s graph until the next full snapshot, which only comes on reconnect.'),
    blank,
    ...sec(r'inbound control requests'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 124-152', r'''
            msg = ws_source.next() => {
                match msg {
                    Some(Ok(Message::Text(text))) => {
                        let Ok(req) = serde_json::from_str::<ControlRequest>(&text) else {
                            warn!("WS client {peer} sent unrecognized control message: {text}");
                            continue;
                        };
                        let resp = handle_control_request(req, &target_tx).await;
                        match serde_json::to_string(&resp) {
                            Ok(json) => {
                                if ws_sink.send(Message::Text(json)).await.is_err() {
                                    info!("WS client {peer} disconnected");
                                    break;
                                }
                            }
                            Err(e) => warn!("control response serialize failed for {peer}: {e}"),
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => {
                        info!("WS client {peer} closed the connection");
                        break;
                    }
                    Some(Err(e)) => {
                        warn!("WS read error for {peer}: {e}");
                        break;
                    }
                    _ => {} // ping/pong/binary/frame — nothing to do
                }
            }'''),
    ...para('//',
        r'A text frame is parsed as a ControlRequest. If it does not parse, the daemon logs the offending text and goes on with continue, not by closing the connection. A parsed request is passed to handle_control_request, and the reply, a ControlResponse, is serialised and sent on the same socket as another text frame. Close, end of stream and a read error each log and break. Ping, pong and binary frames fall into the final arm and are ignored.'),
    blank,
    ...sec(r'pushes'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 153-175', r'''
            push = control_push_rx.recv() => {
                match push {
                    Ok(resp) => match serde_json::to_string(resp.as_ref()) {
                        Ok(json) => {
                            if ws_sink.send(Message::Text(json)).await.is_err() {
                                info!("WS client {peer} disconnected");
                                break;
                            }
                        }
                        Err(e) => warn!("control push serialize failed for {peer}: {e}"),
                    },
                    Err(broadcast::error::RecvError::Lagged(n)) => {
                        warn!("WS client {peer} lagged by {n} control pushes — some dropped");
                    }
                    Err(broadcast::error::RecvError::Closed) => {
                        info!("control push channel closed, dropping WS client {peer}");
                        break;
                    }
                }
            }
        }
    }
}'''),
    ...para('//',
        r'The push arm mirrors the diff arm: serialise, send, and treat Lagged as a log line. The channel capacity is 16 (from main.rs). If the push channel closes, the client is dropped, because that means the daemon is shutting down.'),
    blank,
    ...sec(r'mapping control requests to replies'),
    ...code('rust', r'crates/heaplens-daemon/src/server.rs · lines 177-214', r'''
/// Forwards one control request to the graph task (the single owner of
/// both graph and attach-session state, §3.4) and waits for its reply.
/// `AttachTarget`/`DetachTarget` can take up to a few seconds — they spawn
/// and wait on `heaplens-injector.exe` — but that await only blocks this
/// one client's own task, not the WS server or other connected clients.
async fn handle_control_request(req: ControlRequest, target_tx: &mpsc::UnboundedSender<TargetCmd>) -> ControlResponse {
    match req {
        ControlRequest::ListProcesses => {
            let (reply, rx) = oneshot::channel();
            if target_tx.send(TargetCmd::ListProcesses { reply }).is_err() {
                return ControlResponse::ProcessList { processes: Vec::new() };
            }
            ControlResponse::ProcessList { processes: rx.await.unwrap_or_default() }
        }
        ControlRequest::AttachTarget { pid } => {
            let (reply, rx) = oneshot::channel();
            if target_tx.send(TargetCmd::Attach { pid, reply }).is_err() {
                return ControlResponse::AttachResult { ok: false, message: "daemon graph task is gone".to_owned() };
            }
            match rx.await {
                Ok(Ok(())) => ControlResponse::AttachResult { ok: true, message: format!("attached to pid {pid}") },
                Ok(Err(message)) => ControlResponse::AttachResult { ok: false, message },
                Err(_) => ControlResponse::AttachResult { ok: false, message: "daemon graph task dropped the reply".to_owned() },
            }
        }
        ControlRequest::DetachTarget => {
            let (reply, rx) = oneshot::channel();
            if target_tx.send(TargetCmd::Detach { reply }).is_err() {
                return ControlResponse::DetachResult { ok: false, message: "daemon graph task is gone".to_owned() };
            }
            match rx.await {
                Ok(Ok(())) => ControlResponse::DetachResult { ok: true, message: "detached".to_owned() },
                Ok(Err(message)) => ControlResponse::DetachResult { ok: false, message },
                Err(_) => ControlResponse::DetachResult { ok: false, message: "daemon graph task dropped the reply".to_owned() },
            }
        }
    }
}'''),
    ...para('//',
        r'Each request has the same shape: make a oneshot, send a TargetCmd carrying its sender, await the receiver. The failure branches are where the thinking shows.'),
    blank,
    ...pt('//', r'ListProcesses',
        r'if the graph task is gone the answer is an empty ProcessList. If the reply is dropped, unwrap_or_default gives an empty list. The picker shows nothing instead of an error.'),
    ...pt('//', r'AttachTarget',
        r'success becomes AttachResult { ok: true, message: "attached to pid N" } (the string is built here, not by the injector). Error text from the injector (see injector.rs) is passed through verbatim. A dead graph task and a dropped reply have distinct messages: "daemon graph task is gone" and "daemon graph task dropped the reply".'),
    ...pt('//', r'DetachTarget',
        r'the same with the fixed success text "detached".'),
    ...sec(r'edge cases and a limitation'),
    ...pt('//', r'A long attach stalls that client’s other traffic',
        r'handle_control_request is awaited inside the select arm (line 131), so while the injector is running, the same task is not polling the diff or push receivers. The doc comment says the await "only blocks this one client’s own task, not the WS server or other connected clients", which is accurate, but for that client the diff stream stops for the duration. With a broadcast capacity of 64 and a default tick of 33 ms from config.rs, a multi-second attach could in principle leave more than 64 diffs queued and trigger the Lagged branch when the loop resumes; I have not reproduced it.'),
    ...pt('//', r'Order of arms',
        r'tokio::select! picks randomly among ready branches, so no arm starves the others.'),
    ...pt('//', r'Per-client isolation',
        r'Everything is per-task, a client that fails ends its own task without touching the rest.'),
    ...pt('//', r'Security',
        r'The default address in config.rs is 127.0.0.1:9999, and the tests bind loopback addresses; the server itself does no authentication.'),
    ...sec(r'how it is tested'),
    ...para('//',
        r'ws_tests.rs runs the server against a tiny graph loop and checks the snapshot-then-diff JSON contract and that two clients each get a snapshot. target_diagnostics_stats.rs and cross_process_wire.rs start the same server inside bigger setups. Their pages cover each. The control branch (handle_control_request) is not reached by any test in the repository, since each of those tests creates target_tx and ignores the receiver.'),
    blank,
    ...sec(r'history'),
    ...pt('//', r'9174573 (2026-07-02)',
        r'birth: accept, per-client task, snapshot then diffs.'),
    ...pt('//', r'93bd810 (2026-07-02)',
        r'removed the unwrap chain from the local_addr fallback.'),
    ...pt('//', r'cffa431 (2026-07-02)',
        r'clippy-clean: two needless .into() calls on String removed.'),
    ...pt('//', r'724695a (2026-07-19)',
        r'the Stage 7 port: the receive half of the socket, previously discarded, now read; control requests, pushes and the three-way select appear.'),
    blank,
    link('→ github.com/xynorash/heaplens · crates/heaplens-daemon/src/server.rs',
        'https://github.com/xynorash/heaplens/blob/master/crates/heaplens-daemon/src/server.rs'),
  ],
);
