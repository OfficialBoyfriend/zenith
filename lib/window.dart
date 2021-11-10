import 'package:elinux_app/custom_box_decoration.dart';
import 'package:elinux_app/desktop_state.dart';
import 'package:elinux_app/title_bar.dart';
import 'package:elinux_app/window_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Window extends StatefulWidget {
  final int initialWidth;
  final int initialHeight;
  final int textureId;
  final int viewPtr;

  Window({
    required this.textureId,
    required this.viewPtr,
    required this.initialWidth,
    required this.initialHeight,
  }) : super(key: GlobalKey<LocalWindowState>());

  @override
  LocalWindowState createState() => LocalWindowState();

  WindowState getWindowState() {
    return (key! as GlobalKey<LocalWindowState>).currentState!.windowState;
  }
}

class LocalWindowState extends State<Window> with TickerProviderStateMixin {
  late var windowState = WindowState(
    "Window",
    Rect.fromLTWH(
      100,
      100,
      widget.initialWidth.toDouble(),
      widget.initialHeight.toDouble(),
    ),
    widget.textureId,
  )..activate();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: windowState,
      child: Builder(builder: (context) {
        var windowState = context.watch<WindowState>();
        var desktopState = context.read<DesktopState>();

        return Positioned(
          child: GestureDetector(
            onPanDown: (_) => context.read<DesktopState>().activateWindow(widget),
            child: TweenAnimationBuilder(
              duration: const Duration(milliseconds: 200),
              tween: Tween(begin: 0.9, end: 1.0),
              curve: Curves.linearToEaseOut,
              builder: (BuildContext context, double value, Widget? child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: TweenAnimationBuilder(
                duration: const Duration(milliseconds: 200),
                tween: Tween(begin: 0.0, end: 1.0),
                curve: Curves.linearToEaseOut,
                builder: (BuildContext context, double value, Widget? child) {
                  return Opacity(
                    opacity: value,
                    child: child,
                  );
                },
                child: AnimatedOpacity(
                  curve: Curves.linearToEaseOut,
                  opacity: windowState.opacity,
                  duration: const Duration(milliseconds: 200),
                  child: AnimatedScale(
                    curve: Curves.linearToEaseOut,
                    scale: windowState.scale,
                    duration: const Duration(milliseconds: 200),
                    onEnd: windowState.windowClosed.complete,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      // decoration: CustomBoxDecoration(
                      //   borderRadius: const BorderRadius.all(Radius.circular(10)),
                      //   boxShadow: [
                      //     BoxShadow(
                      //       // spreadRadius: -10,
                      //       blurRadius: windowState.shadowBlurRadius,
                      //     )
                      //   ],
                      // ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        // clipBehavior: Clip.antiAliasWithSaveLayer,
                        child: Material(
                          type: MaterialType.transparency,
                          child: SizedBox(
                            width: windowState.rect.width,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const TitleBar(),
                                if (windowState.textureId != 0)
                                  SizedBox(
                                    width: windowState.rect.width,
                                    height: windowState.rect.height,
                                    child: Listener(
                                      onPointerHover: (PointerHoverEvent event) {
                                        DesktopState.platform.invokeMethod(
                                          "pointer_hover",
                                          {
                                            "x": event.localPosition.dx,
                                            "y": event.localPosition.dy,
                                            "view_ptr": widget.viewPtr,
                                          },
                                        );
                                      },
                                      onPointerMove: (PointerMoveEvent event) {
                                        DesktopState.platform.invokeMethod(
                                          "pointer_hover",
                                          {
                                            "x": event.localPosition.dx,
                                            "y": event.localPosition.dy,
                                            "view_ptr": widget.viewPtr,
                                          },
                                        );
                                      },
                                      child: MouseRegion(
                                        // onEnter: (PointerEnterEvent event) => print("enter"),
                                        // onExit: (PointerExitEvent event) => print("exit"),
                                        child: Texture(
                                          filterQuality: FilterQuality.none,
                                          textureId: windowState.textureId,
                                          // freeze: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (windowState.textureId == 0)
                                  SizedBox(
                                    width: windowState.rect.width,
                                    height: windowState.rect.height,
                                    child: Container(color: Colors.red),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          left: windowState.rect.left,
          top: windowState.rect.top,
          // width: windowState.rect.width,
          // height: windowState.rect.height,
        );
      }),
    );
  }
}
