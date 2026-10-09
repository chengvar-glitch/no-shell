import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/src/ui/selection_mode.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  /// One line per tick: fast enough to cover a screen, slow enough to stop on
  /// the line you want. 16ms (60 lines a second) ran away from the pointer.
  static const _autoScrollInterval = Duration(milliseconds: 50);

  /// Distance from the viewport edge within which a selection drag keeps the
  /// view scrolling.
  static const _autoScrollEdgeZone = 32.0;

  /// Base of the running selection, anchored to a **buffer line** rather than
  /// to a screen position.
  ///
  /// The gesture re-extends the selection every time the view scrolls, and a
  /// base kept as a view position slides along with the content: the text the
  /// user had already selected silently drops out of the range (the highlight
  /// stays the same height and travels with the scroll). Anchoring the base to
  /// the line under the press keeps the whole range selected while it grows.
  CellAnchor? _selectionBase;

  /// True while the running gesture selects whole words (touch long press).
  bool _selectionByWord = false;

  /// Pointer position (view-local) of the running selection drag or long
  /// press; null while none is in progress.
  Offset? _lastDragPointer;

  Timer? _autoScrollTimer;

  int _autoScrollDirection = 0;

  @override
  void dispose() {
    _stopAutoScroll();
    _selectionBase?.dispose();
    _selectionBase = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCancel: onDragCancel,
      onDoubleTapDown: onDoubleTapDown,
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastDragPointer = details.localPosition;
    _startSelection(details.localPosition, byWord: true);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _lastDragPointer = details.localPosition;
    _updateAutoScroll();
    _extendSelection(details.localPosition);
  }

  void onLongPressUp() {
    _endSelection();
  }

  void onDragStart(DragStartDetails details) {
    // A mouse pan is not a long press: start a fresh selection in the mode of
    // the gesture that won.
    _lastDragPointer = details.localPosition;
    _startSelection(
      details.localPosition,
      byWord: details.kind != PointerDeviceKind.mouse,
    );
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragPointer = details.localPosition;
    _updateAutoScroll();
    _extendSelection(details.localPosition);
  }

  void onDragEnd(DragEndDetails details) {
    _endSelection();
  }

  void onDragCancel() {
    _endSelection();
  }

  /// Begin a selection at [pointer]: remember the cell under it as the
  /// (buffer-anchored) base, and lay down what the press alone selects — one
  /// cell for a mouse drag, the word under the finger for a long press.
  void _startSelection(Offset pointer, {required bool byWord}) {
    _selectionBase?.dispose();
    _selectionByWord = byWord;
    final buffer = terminalView.widget.terminal.buffer;
    final cell = renderTerminal.getCellOffset(pointer);
    _selectionBase = buffer.createAnchor(cell.x, cell.y);
    if (byWord) {
      renderTerminal.selectWord(pointer);
    } else {
      renderTerminal.selectCharacters(pointer);
    }
  }

  /// Extend the selection to the cell under [pointer], keeping the base on the
  /// text the gesture started from — see [_selectionBase].
  void _extendSelection(Offset pointer) {
    final base = _selectionBase;
    if (base == null || !base.attached) return;
    final buffer = terminalView.widget.terminal.buffer;
    final from = base.offset;
    final to = renderTerminal.getCellOffset(pointer);
    if (_selectionByWord) {
      final fromBoundary = buffer.getWordBoundary(from);
      final toBoundary = buffer.getWordBoundary(to);
      // A blank cell has no word to snap to; leave the range where it was
      // (same rule as the plain word selection).
      if (fromBoundary == null || toBoundary == null) return;
      final range = fromBoundary.merge(toBoundary);
      widget.terminalController.setSelection(
        buffer.createAnchorFromOffset(range.begin),
        buffer.createAnchorFromOffset(range.end),
        mode: SelectionMode.line,
      );
      return;
    }
    // The character drag includes the cell the pointer sits on when moving
    // forwards, so the extent goes one past it. Every `setSelection` takes
    // fresh anchors: it disposes the pair it was given last time.
    var end = to;
    if (end.x >= from.x) end = CellOffset(end.x + 1, end.y);
    widget.terminalController.setSelection(
      buffer.createAnchor(from.x, from.y),
      buffer.createAnchor(end.x, end.y),
    );
  }

  /// Stop scrolling and release the base anchor. The anchors handed to the
  /// controller are fresh ones (see [_extendSelection]), so this one is ours
  /// to dispose.
  void _endSelection() {
    _stopAutoScroll();
    _selectionBase?.dispose();
    _selectionBase = null;
  }

  /// Keep scrolling while a selection drag holds the pointer inside the edge
  /// zone at the top / bottom of the viewport (rubber-band feel, as in native
  /// terminal emulators).
  void _updateAutoScroll() {
    // Either gesture kind drives auto-scroll: mouse pans via [onDragUpdate],
    // touch long-press word selection via [onLongPressMoveUpdate].
    if (_lastDragPointer == null || _selectionBase == null) return;
    if (terminalView.widget.terminal.isUsingAltBuffer) return;

    final direction = _autoScrollDirectionOf(_lastDragPointer!);
    if (direction == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollDirection = direction;
    _autoScrollTimer ??= Timer.periodic(_autoScrollInterval, (_) {
      _autoScrollTick();
    });
  }

  /// -1 to scroll toward the scrollback (top edge), +1 toward newer lines
  /// (bottom edge), 0 when the pointer is outside both edge zones.
  ///
  /// The sign matches [_autoScrollTick]'s `pixels + direction * lineHeight`
  /// and its stop conditions: a bigger offset shows newer rows, so the top
  /// edge must decrease the offset. Returning the opposite signs here made a
  /// selection dragged past the *bottom* edge run away into the scrollback
  /// (the view scrolled up and only stopped at the very top) — exactly the
  /// newest lines the user was trying to copy.
  int _autoScrollDirectionOf(Offset pointer) {
    final height = renderTerminal.size.height;
    if (pointer.dy < _autoScrollEdgeZone) return -1;
    if (pointer.dy > height - _autoScrollEdgeZone) return 1;
    return 0;
  }

  void _autoScrollTick() {
    if (!terminalView.scrollController.hasClients ||
        _lastDragPointer == null ||
        _selectionBase == null ||
        // Entering the alternate screen mid-drag removes the scrollback this
        // scrolling assumes.
        terminalView.widget.terminal.isUsingAltBuffer) {
      _stopAutoScroll();
      return;
    }

    final pixels = terminalView.scrollController.position.pixels;
    final lineHeight = renderTerminal.lineHeight;
    // The real top of the scrollback: render maps offset directly to buffer
    // rows and clamps them, so overshooting would pile the selection on the
    // last visible row instead of stopping.
    final maxOffset = math.max(
      0.0,
      terminalView.widget.terminal.buffer.lines.length * lineHeight -
          renderTerminal.size.height,
    );

    switch (_autoScrollDirection) {
      case 1 when pixels >= maxOffset:
      case -1 when pixels <= 0:
        _stopAutoScroll();
        return;
    }
    // Clamp the last step: it would otherwise land one line past the edge and
    // stay there (nothing snaps the offset back once the tick stops), which
    // shows as a blank strip above the first line.
    terminalView.scrollController.jumpTo(
      (pixels + _autoScrollDirection * lineHeight).clamp(0.0, maxOffset),
    );

    // The pointer has not moved, but the cell under it changed with the
    // scroll: extend the selection again — the base stays on the text the
    // gesture started from, so the range grows instead of sliding along.
    _extendSelection(_lastDragPointer!);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
    _lastDragPointer = null;
  }
}
