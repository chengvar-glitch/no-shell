import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

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

  static const _autoScrollInterval = Duration(milliseconds: 16);

  /// Distance from the viewport edge within which a selection drag keeps the
  /// view scrolling.
  static const _autoScrollEdgeZone = 32.0;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  /// Pointer position (view-local) of the running selection drag or long
  /// press; null while none is in progress.
  Offset? _lastDragPointer;

  Timer? _autoScrollTimer;

  int _autoScrollDirection = 0;

  @override
  void dispose() {
    _stopAutoScroll();
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
    _lastLongPressStartDetails = details;
    _lastDragPointer = details.localPosition;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _lastDragPointer = details.localPosition;
    _updateAutoScroll();
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onLongPressUp() {
    _lastLongPressStartDetails = null;
    _stopAutoScroll();
  }

  void onDragStart(DragStartDetails details) {
    // A mouse pan is not a long press: drop any stale long-press origin so
    // the auto-scroll tick re-selects in the mode of the active gesture.
    _lastLongPressStartDetails = null;
    _stopAutoScroll();
    _lastDragStartDetails = details;
    _lastDragPointer = details.localPosition;

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastDragPointer = details.localPosition;
    _updateAutoScroll();
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragEnd(DragEndDetails details) {
    _stopAutoScroll();
  }

  void onDragCancel() {
    _stopAutoScroll();
  }

  /// Keep scrolling while a selection drag holds the pointer inside the edge
  /// zone at the top / bottom of the viewport, and re-extend the selection
  /// from the same view positions so the selection follows the scrolled
  /// content (rubber-band feel, as in native terminal emulators).
  void _updateAutoScroll() {
    // Either gesture kind drives auto-scroll: mouse pans via [onDragUpdate],
    // touch long-press word selection via [onLongPressMoveUpdate].
    final drag = _lastDragStartDetails;
    final press = _lastLongPressStartDetails;
    if (_lastDragPointer == null || (drag == null && press == null)) return;
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

  /// -1 to scroll toward newer lines (bottom edge), +1 toward the scrollback
  /// (top edge), 0 when the pointer is outside both edge zones.
  int _autoScrollDirectionOf(Offset pointer) {
    final height = renderTerminal.size.height;
    if (pointer.dy < _autoScrollEdgeZone) return 1;
    if (pointer.dy > height - _autoScrollEdgeZone) return -1;
    return 0;
  }

  void _autoScrollTick() {
    final drag = _lastDragStartDetails;
    final press = _lastLongPressStartDetails;
    if (!terminalView.scrollController.hasClients ||
        _lastDragPointer == null ||
        (drag == null && press == null) ||
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
    terminalView.scrollController.jumpTo(
      pixels + _autoScrollDirection * lineHeight,
    );

    // The pointer has not moved, but the cell under it changed with the
    // scroll: re-run the selection with the same view positions.
    final start = press?.localPosition ?? drag!.localPosition;
    if (press != null) {
      renderTerminal.selectWord(start, _lastDragPointer!);
    } else {
      renderTerminal.selectCharacters(start, _lastDragPointer!);
    }
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDirection = 0;
    _lastDragPointer = null;
  }
}
