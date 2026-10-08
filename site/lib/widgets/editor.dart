import 'dart:async';

import 'package:flutter/material.dart';

import '../models/project.dart';
import '../platform/web_io.dart' as io;
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'style.dart';

const double kLineExtent = 22;
const double _kGutter = 56;
const double _kFontSize = 13;

/// One rendered row: a logical line, or a wrapped continuation of one.
class _Row {
  final int logical;
  final bool first;
  final List<Span> spans;
  const _Row(this.logical, this.first, this.spans);
}

/// Slices [spans] to the character range [start, end), keeping styles/links.
List<Span> _slice(List<Span> spans, int start, int end) {
  final out = <Span>[];
  var pos = 0;
  for (final sp in spans) {
    final a = pos, b = pos + sp.text.length;
    pos = b;
    if (b <= start || a >= end) continue;
    final from = (start - a).clamp(0, sp.text.length);
    final to = (end - a).clamp(0, sp.text.length);
    if (to > from) out.add(Span(sp.text.substring(from, to), sp.tok, url: sp.url));
  }
  return out;
}

/// Soft-wraps one logical line to [cols] columns at word boundaries, with a
/// hanging indent that matches the line's own leading whitespace. Monospace,
/// so column math is just character counts.
List<List<Span>> wrapSpans(List<Span> spans, int cols) {
  final text = spans.map((s) => s.text).join();
  if (text.length <= cols) return [spans];
  final indent = text.length - text.trimLeft().length;
  final hang = indent.clamp(0, cols ~/ 3);
  final rows = <List<Span>>[];
  var start = 0;
  var first = true;
  while (start < text.length) {
    final width = first ? cols : cols - hang;
    var end = start + width;
    if (end >= text.length) {
      end = text.length;
    } else {
      final sp = text.lastIndexOf(' ', end);
      if (sp > start + 1) end = sp;
    }
    var row = _slice(spans, start, end);
    if (!first && hang > 0) row = [Span(' ' * hang, Tok.plain), ...row];
    rows.add(row);
    start = end;
    while (start < text.length && text[start] == ' ') {
      start++;
    }
    first = false;
  }
  return rows;
}

class EditorPane extends StatefulWidget {
  final AppState state;
  const EditorPane({super.key, required this.state});

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  final _scroll = ScrollController();
  int _lastLine = 0;
  int _lastBuffer = 0;
  bool _cursorOn = true;
  bool _programmatic = false;
  List<int> _firstRow = const [];
  List<_Row> _rows = const [];
  Timer? _blink;

  @override
  void initState() {
    super.initState();
    _lastBuffer = widget.state.bufferIndex;
    _lastLine = widget.state.scrollLines;
    widget.state.addListener(_onState);
    _scroll.addListener(_onScroll);
    _blink = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _cursorOn = !_cursorOn);
    });
  }

  @override
  void dispose() {
    _blink?.cancel();
    widget.state.removeListener(_onState);
    _scroll.dispose();
    super.dispose();
  }

  void _onState() {
    final s = widget.state;
    if (!_scroll.hasClients) return;
    if (s.bufferIndex != _lastBuffer) {
      _lastBuffer = s.bufferIndex;
      _lastLine = s.scrollLines;
      _scroll.jumpTo(0);
      return;
    }
    if (s.scrollLines != _lastLine) {
      _lastLine = s.scrollLines;
      final row = s.scrollLines < _firstRow.length
          ? _firstRow[s.scrollLines]
          : s.scrollLines;
      final target =
          (row * kLineExtent).clamp(0.0, _scroll.position.maxScrollExtent);
      _programmatic = true;
      _scroll
          .animateTo(target,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut)
          .whenComplete(() {
        _programmatic = false;
        _onScroll();
      });
    }
  }

  /// Wheel / touch / scrollbar scrolling updates the statusline position
  /// (line:col and percentage) instead of leaving it frozen at 1:1.
  void _onScroll() {
    if (_programmatic || !_scroll.hasClients || _rows.isEmpty) return;
    final r = (_scroll.offset / kLineExtent).round().clamp(0, _rows.length - 1);
    final logical = _rows[r].logical;
    if (logical == widget.state.scrollLines) return;
    _lastLine = logical;
    // Offset changes can happen mid-layout; notify after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.state.syncScroll(logical);
    });
  }

  TextStyle _tokStyle(Tok tok, AppTheme t) => switch (tok) {
        Tok.comment => mono(t.muted, style: FontStyle.italic),
        Tok.keyword => mono(t.purple),
        Tok.string => mono(t.green),
        Tok.fn => mono(t.blue),
        Tok.type => mono(t.yellow),
        Tok.plain => mono(t.fg),
        Tok.punct => mono(t.fgDim),
        Tok.heading => mono(t.accent, weight: FontWeight.w700),
        Tok.link => mono(t.cyan, decoration: TextDecoration.underline),
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final t = s.themeController.theme;
    final b = s.buffer;

    final lines = [...b.lines];
    if (b.repo != null) {
      final stats = s.stats[b.repo];
      final stars = stats?.stars ?? b.fallbackStars;
      final pushed = stats?.pushedAt ?? b.fallbackPushed;
      lines.add(const CodeLine([Span(' ', Tok.plain)]));
      lines.add(CodeLine([
        Span('★ $stars', Tok.type),
        Span(' · last push $pushed', Tok.comment),
      ]));
    }
    const tildes = 8;

    return Container(
      color: t.bg,
      child: LayoutBuilder(builder: (context, box) {
        // Measure one monospace column to know how many fit; narrow
        // screens wrap instead of clipping text off the right edge.
        final tp = TextPainter(
          text: TextSpan(text: 'M' * 20, style: mono(t.fg, size: _kFontSize)),
          textDirection: TextDirection.ltr,
        )..layout();
        final charW = tp.width / 20;
        final cols = ((box.maxWidth - _kGutter - 16) / charW)
            .floor()
            .clamp(24, 400);

        final rows = <_Row>[];
        final firstRow = <int>[];
        for (var i = 0; i < lines.length; i++) {
          firstRow.add(rows.length);
          final parts = wrapSpans(lines[i].spans, cols);
          for (var k = 0; k < parts.length; k++) {
            rows.add(_Row(i, k == 0, parts[k]));
          }
        }
        _rows = rows;
        _firstRow = firstRow;

        return ListView.builder(
          controller: _scroll,
          itemExtent: kLineExtent,
          itemCount: rows.length + tildes,
          itemBuilder: (_, i) {
            if (i >= rows.length) {
              return Row(children: [
                SizedBox(
                  width: _kGutter,
                  child: Text('~  ',
                      textAlign: TextAlign.right, style: mono(t.lineNr)),
                ),
              ]);
            }
            final row = rows[i];
            final isCursorLine = row.logical == s.scrollLines;
            return Container(
              color: isCursorLine
                  ? t.bgHighlight.withValues(alpha: 0.55)
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _kGutter,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(row.first ? '${row.logical + 1}' : '',
                          textAlign: TextAlign.right,
                          style: mono(isCursorLine ? t.accent : t.lineNr)),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (final span in row.spans)
                            span.url == null
                                ? TextSpan(
                                    text: span.text,
                                    style: _tokStyle(span.tok, t))
                                : WidgetSpan(
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: GestureDetector(
                                        onTap: () => io.openUrl(span.url!),
                                        child: Text(span.text,
                                            style: _tokStyle(span.tok, t)),
                                      ),
                                    ),
                                  ),
                          if (isCursorLine && row.first)
                            TextSpan(
                              text: '▊',
                              style: mono(t.fg.withValues(
                                  alpha: _cursorOn ? 0.9 : 0.0)),
                            ),
                        ],
                      ),
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}
