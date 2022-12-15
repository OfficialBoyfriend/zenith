import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:zenith/enums.dart';
import 'package:zenith/state/lock_screen_state.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> with SingleTickerProviderStateMixin {
  late AnimationController _showAuthenticationAnimationController;
  Animation? _slideAnimation;

  @override
  void initState() {
    super.initState();
    _showAuthenticationAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200), // Duration is irrelevant because of .fling().
      vsync: this,
    );
  }

  @override
  void dispose() {
    _showAuthenticationAnimationController.dispose();
    super.dispose();
  }

  void _updateOffset() {
    ref.read(lockScreenStateProvider.notifier).offset = _slideAnimation!.value;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(lockScreenStateProvider.select((v) => v.dragging), (_, bool dragging) {
      LockScreenState state = ref.read(lockScreenStateProvider);
      double velocity = state.dragVelocity;

      if (dragging) {
        _showAuthenticationAnimationController.stop();
      } else {
        _slideAnimation?.removeListener(_updateOffset);

        if (velocity.abs() > 300) {
          if (velocity.isNegative) {
            _slideAnimation = Tween(
              begin: state.offset,
              end: state.slideDistance,
            ).animate(_showAuthenticationAnimationController);
          } else {
            _slideAnimation = Tween(
              begin: state.offset,
              end: 0.0,
            ).animate(_showAuthenticationAnimationController);
          }
        } else {
          double progression = state.offset / state.slideDistance;
          if (progression >= 0.5) {
            _slideAnimation = Tween(
              begin: state.offset,
              end: state.slideDistance,
            ).animate(_showAuthenticationAnimationController);
          } else {
            _slideAnimation = Tween(
              begin: state.offset,
              end: 0.0,
            ).animate(_showAuthenticationAnimationController);
          }
        }
        _slideAnimation!.addListener(_updateOffset);
        _showAuthenticationAnimationController
          ..reset()
          ..fling(velocity: velocity.abs() / 50);
      }
    });

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset("assets/images/background.jpg", fit: BoxFit.cover),
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final offset = ref.watch(lockScreenStateProvider.select((v) => v.offset));
            final slideDistance = ref.watch(lockScreenStateProvider.select((v) => v.slideDistance));
            double progression = offset / slideDistance;

            const double maxBlurAmount = 30;
            double blurAmount = progression <= 0.5 ? 0 : maxBlurAmount * 2 * (progression - 0.5);

            return BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurAmount,
                sigmaY: blurAmount,
              ),
              child: child,
            );
          },
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 0,
              sigmaY: 0,
            ),
            child: Stack(
              children: [
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, Widget? child) {
                    double offset = ref.watch(lockScreenStateProvider.select((value) => value.offset));
                    double slideDistance = ref.watch(lockScreenStateProvider.select((value) => value.slideDistance));
                    double progression = offset / slideDistance;

                    return IgnorePointer(
                      ignoring: progression >= 0.5,
                      child: Transform.translate(
                        offset: Offset(0, -offset),
                        child: Opacity(
                          opacity: (1.0 - offset / (slideDistance / 2)).clamp(0.0, 1.0),
                          child: const Clock(),
                        ),
                      ),
                    );
                  },
                ),
                Consumer(
                  builder: (BuildContext context, WidgetRef ref, Widget? child) {
                    double offset = ref.watch(lockScreenStateProvider.select((value) => value.offset));
                    double slideDistance = ref.watch(lockScreenStateProvider.select((value) => value.slideDistance));
                    double progression = offset / slideDistance;

                    return IgnorePointer(
                      ignoring: progression < 0.5,
                      child: Transform.translate(
                        offset: Offset(0, slideDistance - offset),
                        child: Opacity(
                          opacity: (offset / (slideDistance / 2) - 1.0).clamp(0.0, 1.0),
                          child: const PinAuthentication(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        GestureDetector(
          onPanStart: (DragStartDetails details) {
            ref.read(lockScreenStateProvider.notifier).startDrag();
          },
          onPanUpdate: (DragUpdateDetails details) {
            ref.read(lockScreenStateProvider.notifier).drag(-details.delta.dy);
          },
          onPanEnd: (DragEndDetails details) {
            ref.read(lockScreenStateProvider.notifier).endDrag(details.velocity.pixelsPerSecond.dy);
          },
        )
      ],
    );
  }
}

const _shadow = Shadow(
  color: Colors.black45,
  blurRadius: 10,
);

class Clock extends StatefulWidget {
  const Clock({super.key});

  @override
  State<Clock> createState() => _ClockState();
}

class _ClockState extends State<Clock> {
  final DateFormat _format = DateFormat.MMMMEEEEd();
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Stack(
      children: [
        Positioned(
          left: 50,
          top: 50,
          child: Text(
            _format.format(now),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              shadows: [_shadow],
            ),
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: DefaultTextStyle(
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 200,
              fontWeight: FontWeight.normal,
              height: 0.8,
              shadows: [_shadow],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${now.hour}".padLeft(2, '0')),
                Text("${now.minute}".padLeft(2, '0')),
              ],
            ),
          ),
        ),
        const Positioned(
          bottom: 200,
          left: 0,
          right: 0,
          child: Icon(
            Icons.lock,
            color: Colors.white,
            size: 50,
            shadows: [_shadow],
          ),
        ),
      ],
    );
  }
}

class PinAuthentication extends StatefulWidget {
  const PinAuthentication({super.key});

  @override
  State<PinAuthentication> createState() => _PinAuthenticationState();
}

class _PinAuthenticationState extends State<PinAuthentication> {
  late TextEditingController _pinTextController;

  @override
  void initState() {
    super.initState();
    _pinTextController = TextEditingController();
  }

  @override
  void dispose() {
    _pinTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void enterDigit(String digit) {
      _pinTextController.text += digit;
    }

    void backspace() {
      if (_pinTextController.text.isNotEmpty) {
        _pinTextController.text = _pinTextController.text.substring(0, _pinTextController.text.length - 1);
      }
    }

    void clear() {
      _pinTextController.clear();
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 200,
            child: ValueListenableBuilder(
              valueListenable: _pinTextController,
              builder: (BuildContext context, TextEditingValue value, Widget? child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.filled(
                    value.text.length,
                    const Text(
                      "●",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                      ),
                    ),
                  ).interleave(const SizedBox(width: 20)).toList(),
                );
              },
            ),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pinButton(Text("1"), () => enterDigit("1")),
                    pinButton(Text("2"), () => enterDigit("2")),
                    pinButton(Text("3"), () => enterDigit("3")),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pinButton(Text("4"), () => enterDigit("4")),
                    pinButton(Text("5"), () => enterDigit("5")),
                    pinButton(Text("6"), () => enterDigit("6")),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pinButton(Text("7"), () => enterDigit("7")),
                    pinButton(Text("8"), () => enterDigit("8")),
                    pinButton(Text("9"), () => enterDigit("9")),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    pinButton(
                      Icon(
                        Icons.backspace,
                        color: Colors.white,
                      ),
                      backspace,
                      clear,
                    ),
                    pinButton(Text("0"), () => enterDigit("0")),
                    pinButton(
                      Icon(
                        Icons.check,
                        color: Colors.white,
                      ),
                      () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget pinButton(Widget child, VoidCallback onTap, [VoidCallback? onLongPress]) {
  return Padding(
    padding: const EdgeInsets.all(10.0),
    child: SizedBox.fromSize(
      size: const Size(100, 100),
      child: ClipOval(
        child: Material(
          color: Colors.white12,
          child: InkWell(
            splashColor: Colors.white24,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Center(
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
