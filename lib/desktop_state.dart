import 'package:provider/provider.dart';
import 'package:zenith/enums.dart';
import 'package:zenith/popup.dart';
import 'package:zenith/popup_state.dart';
import 'package:zenith/util.dart';
import 'package:zenith/window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zenith/window_state.dart';

class DesktopState with ChangeNotifier {
  List<Window> windows = [];
  List<Popup> popups = [];

  static const EventChannel windowMappedEvent = EventChannel('window_mapped');
  static const EventChannel windowUnmappedEvent = EventChannel('window_unmapped');
  static const EventChannel popupMappedEvent = EventChannel('popup_mapped');
  static const EventChannel popupUnmappedEvent = EventChannel('popup_unmapped');
  static const EventChannel requestMoveEvent = EventChannel('request_move');
  static const EventChannel requestResizeEvent = EventChannel('request_resize');
  static const EventChannel configureSurfaceEvent = EventChannel('configure_surface');
  static const MethodChannel platform = MethodChannel('platform');

  DesktopState() {
    windowMappedEvent.receiveBroadcastStream().listen((event) {
      int viewId = event["view_id"];
      int surfaceWidth = event["surface_width"];
      int surfaceHeight = event["surface_height"];

      var visibleBoundsMap = Map<String, int>.from(event["visible_bounds"]);
      var visibleBounds = Rect.fromLTWH(
        visibleBoundsMap["x"]!.toDouble(),
        visibleBoundsMap["y"]!.toDouble(),
        visibleBoundsMap["width"]!.toDouble(),
        visibleBoundsMap["height"]!.toDouble(),
      );

      windows.add(
        Window(WindowState(
          viewId: viewId,
          title: "Window",
          position: const Offset(100, 100),
          surfaceSize: Size(surfaceWidth.toDouble(), surfaceHeight.toDouble()),
          visibleBounds: visibleBounds,
        )),
      );
      notifyListeners();
    });

    windowUnmappedEvent.receiveBroadcastStream().listen((event) async {
      int viewId = event["view_id"];

      var window = windows.singleWhere((element) => element.state.viewId == viewId);
      await window.state.animateClosing();

      windows.remove(window);
      notifyListeners();
    });

    popupMappedEvent.receiveBroadcastStream().listen((event) {
      int viewId = event["view_id"];
      int parentViewId = event["parent_view_id"];
      int x = event["x"];
      int y = event["y"];
      int width = event["surface_width"];
      int height = event["surface_height"];
      var visibleBoundsMap = event["visible_bounds"];
      var visibleBounds = Rect.fromLTWH(
        visibleBoundsMap["x"]!.toDouble(),
        visibleBoundsMap["y"]!.toDouble(),
        visibleBoundsMap["width"]!.toDouble(),
        visibleBoundsMap["height"]!.toDouble(),
      );

      // Parent can be either a window or another popup.
      Offset parentPosition;
      var windowIndex = windows.indexWhere((element) => element.state.viewId == parentViewId);
      if (windowIndex != -1) {
        var window = windows[windowIndex];
        parentPosition = window.state.position + window.state.visibleBounds.topLeft;
      } else {
        var popupIndex = popups.indexWhere((element) => element.state.viewId == parentViewId);
        var popup = popups[popupIndex];
        parentPosition = popup.state.position;
      }

      var popup = Popup(PopupState(
        viewId: viewId,
        parentViewId: parentViewId,
        position: Offset(x + parentPosition.dx, y + parentPosition.dy),
        surfaceSize: Size(width.toDouble(), height.toDouble()),
        visibleBounds: visibleBounds,
      ));

      popups.add(popup);
      notifyListeners();
    });

    popupUnmappedEvent.receiveBroadcastStream().listen((event) async {
      int viewId = event["view_id"];

      var popup = popups.singleWhere((element) => element.state.viewId == viewId);
      await popup.state.animateClosing();
      print("delete");

      popups.remove(popup);
      notifyListeners();
    });

    requestMoveEvent.receiveBroadcastStream().listen((event) {
      int viewId = event["view_id"];

      var window = windows.singleWhere((element) => element.state.viewId == viewId);
      window.state.startMove();
    });

    requestResizeEvent.receiveBroadcastStream().listen((event) {
      int viewId = event["view_id"];
      int edges = event["edges"];

      var window = windows.singleWhere((element) => element.state.viewId == viewId);
      window.state.startResize(edges);
    });

    configureSurfaceEvent.receiveBroadcastStream().listen((event) {
      int viewId = event["view_id"];
      var role = XdgSurfaceRole.values[event["surface_role"]];

      Size? surfaceSize;
      if (event["surface_size_changed"]) {
        int surfaceWidth = event["surface_width"];
        int surfaceHeight = event["surface_height"];
        surfaceSize = Size(surfaceWidth.toDouble(), surfaceHeight.toDouble());
      }

      Rect? visibleBounds;
      if (event["geometry_changed"]) {
        var visibleBoundsMap = event["visible_bounds"];
        visibleBounds = Rect.fromLTWH(
          visibleBoundsMap["x"]!.toDouble(),
          visibleBoundsMap["y"]!.toDouble(),
          visibleBoundsMap["width"]!.toDouble(),
          visibleBoundsMap["height"]!.toDouble(),
        );
      }

      Offset? position;
      if (role == XdgSurfaceRole.popup && event["popup_position_changed"]) {
        int x = event["x"];
        int y = event["y"];
        position = Offset(x.toDouble(), y.toDouble());
      }

      switch (role) {
        case XdgSurfaceRole.toplevel:
          var window = windows.singleWhere((element) => element.state.viewId == viewId);
          window.state.surfaceSize = surfaceSize ?? window.state.surfaceSize;
          window.state.visibleBounds = visibleBounds ?? window.state.visibleBounds;
          break;
        case XdgSurfaceRole.popup:
          var popup = popups.singleWhere((element) => element.state.viewId == viewId);
          popup.state.surfaceSize = surfaceSize ?? popup.state.surfaceSize;
          popup.state.visibleBounds = visibleBounds ?? popup.state.visibleBounds;

          Offset parentPosition;
          var windowIndex = windows.indexWhere((element) => element.state.viewId == popup.state.parentViewId);
          if (windowIndex != -1) {
            var window = windows[windowIndex];
            parentPosition = window.state.position + window.state.visibleBounds.topLeft;
          } else {
            var popupIndex = popups.indexWhere((element) => element.state.viewId == popup.state.parentViewId);
            var parentPopup = popups[popupIndex];
            parentPosition = parentPopup.state.position;
          }

          if (position != null) {
            popup.state.position = position + parentPosition;
          }
          break;
        case XdgSurfaceRole.none:
          assert(false, "xdg_surface has no role, this should never happen.");
          break;
      }
    });
  }

  void activateWindow(int viewId) {
    var window = windows.singleWhere((window) => window.state.viewId == viewId);
    // Put it in the front.
    windows.remove(window);
    windows.add(window);

    platform.invokeMethod('activate_window', window.state.viewId);
    notifyListeners();
  }

  void destroyWindow(Window window) {
    windows.remove(window);
    notifyListeners();
  }
}
