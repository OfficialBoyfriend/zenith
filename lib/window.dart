import 'package:flutter/cupertino.dart';
import 'package:zenith/clip_hitbox.dart';
import 'package:zenith/desktop_state.dart';
import 'package:zenith/util.dart';
import 'package:zenith/window_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Window extends StatelessWidget {
  final WindowState state;

  Window(this.state) : super(key: GlobalKey());

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => state,
      child: const _PointerListener(
        child: _Animations(
          child: _Surface(),
        ),
      ),
    );
  }
}

Offset delta = Offset.zero;

class _PointerListener extends StatelessWidget {
  final Widget child;

  const _PointerListener({required this.child});

  @override
  Widget build(BuildContext context) {
    var position = context.select((WindowState state) => state.position).rounded();
    var isClosing = context.select((WindowState state) => state.isClosing);
    var isMoving = context.select((WindowState state) => state.isMoving);
    var isResizing = context.select((WindowState state) => state.isResizing);

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        ignoring: isClosing,
        child: Listener(
          onPointerDown: (_) {
            var windowState = context.read<WindowState>();
            context.read<DesktopState>().activateWindow(windowState.viewId);
          },
          onPointerMove: (PointerMoveEvent event) {
            var windowState = context.read<WindowState>();
            if (isMoving) {
              windowState.position += event.delta;
            }
            if (isResizing) {
              var bounds = windowState.visibleBoundsResize;
              windowState.visibleBoundsResize = Rect.fromLTWH(
                bounds.left,
                bounds.top,
                bounds.width + event.delta.dx,
                bounds.height + event.delta.dy,
              );
              DesktopState.platform.invokeMethod(
                "resize_window",
                {
                  "view_id": windowState.viewId,
                  "width": windowState.visibleBoundsResize.width,
                  "height": windowState.visibleBoundsResize.height,
                },
              );
            }
          },
          onPointerUp: (_) {
            context.read<WindowState>().stopMove();
            context.read<WindowState>().stopResize();
          },
          child: child,
        ),
      ),
    );
  }
}

class _Animations extends StatelessWidget {
  final Widget child;

  const _Animations({required this.child});

  @override
  Widget build(BuildContext context) {
    var opacity = context.select((WindowState state) => state.opacity);
    var scale = context.select((WindowState state) => state.scale);

    return AnimatedOpacity(
      curve: Curves.easeOutCubic,
      opacity: opacity,
      duration: const Duration(milliseconds: 200),
      child: AnimatedScale(
        curve: Curves.easeOutCubic,
        scale: scale,
        duration: const Duration(milliseconds: 200),
        onEnd: () {
          var windowState = context.read<WindowState>();
          if (windowState.isClosing) {
            windowState.windowClosed.complete();
          }
        },
        child: child,
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var windowState = context.read<WindowState>();
    var size = context.select((WindowState state) => state.surfaceSize);
    var bounds = context.select((WindowState state) => state.visibleBounds);
    const invisibleResizeBorder = 10.0;

    return ClipHitbox(
      clipper: RectClip(bounds.inflate(invisibleResizeBorder)),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Listener(
            onPointerDown: (event) => pointerMoved(context, event),
            onPointerUp: (event) => pointerMoved(context, event),
            onPointerHover: (event) => pointerMoved(context, event),
            onPointerMove: (event) => pointerMoved(context, event),
            child: Texture(
              key: windowState.textureKey,
              filterQuality: FilterQuality.none,
              textureId: windowState.viewId,
            ),
          ),
        ),
      ),
    );
  }

  void pointerMoved(BuildContext context, PointerEvent event) {
    var windowState = context.read<WindowState>();

    if (windowState.isMoving) {
      // FIXME: Work around a Flutter bug where the Listener widget wouldn't move with the window and would
      // give coordinates relative to the window position before moving it.
      // Make sure to include the window movement.
      windowState.movingDelta += event.delta;
    }
    var pos = event.localPosition - windowState.movingDelta;

    DesktopState.platform.invokeMethod(
      "pointer_hover",
      {
        "x": pos.dx,
        "y": pos.dy,
        "view_id": windowState.viewId,
      },
    );
  }
}
