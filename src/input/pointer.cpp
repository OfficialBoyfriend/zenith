/*
 * Pointer support is not perfectly implemented
 */

#include "pointer.hpp"
#include "server.hpp"
#include "time.hpp"

extern "C" {
#define static
#include "wlr/types/wlr_pointer.h"
#undef static
}

ZenithPointer::ZenithPointer(ZenithServer* server)
	  : server(server) {
	/*
	 * Creates a cursor, which is a wlroots utility for tracking the cursor
	 * image shown on screen.
	 */
	cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(cursor, server->output_layout);

	/* Creates an xcursor manager, another wlroots utility which loads up
     * Xcursor themes to source cursor images from and makes sure that cursor
     * images are available at all scale factors on the screen (necessary for
     * HiDPI support). We add a cursor theme at scale factor 1 to begin with. */
	cursor_mgr = wlr_xcursor_manager_create(nullptr, 20);
	wlr_xcursor_manager_load(cursor_mgr, 1);

	/*
	 * wlr_cursor *only* displays an image on screen. It does not move around
	 * when the pointer moves. However, we can attach input devices to it, and
	 * it will generate aggregate events for all of them. In these events, we
	 * can choose how we want to process them, forwarding them to clients and
	 * moving the cursor around. More detail on this process is described in my
	 * input handling blog post:
	 *
	 * https://drewdevault.com/2018/07/17/Input-handling-in-wlroots.html
	 *
	 * And more comments are sprinkled throughout the notify functions above.
	 */
	cursor_motion.notify = server_cursor_motion;
	wl_signal_add(&cursor->events.motion, &cursor_motion);

	cursor_motion_absolute.notify = server_cursor_motion_absolute;
	wl_signal_add(&cursor->events.motion_absolute, &cursor_motion_absolute);

	cursor_button.notify = server_cursor_button;
	wl_signal_add(&cursor->events.button, &cursor_button);

	cursor_axis.notify = server_cursor_axis;
	wl_signal_add(&cursor->events.axis, &cursor_axis);

	cursor_frame.notify = server_cursor_frame;
	wl_signal_add(&cursor->events.frame, &cursor_frame);
}

void server_cursor_motion(wl_listener* listener, void* data) {
	ZenithPointer* pointer = wl_container_of(listener, pointer, cursor_motion);
	ZenithServer* server = pointer->server;
	auto* event = static_cast<wlr_event_pointer_motion*>(data);

	if (server->output == nullptr) {
		return;
	}

	pointer->set_visible(true);

	/* The cursor doesn't move unless we tell it to. The cursor automatically
	 * handles constraining the motion to the output layout, as well as any
	 * special configuration applied for the specific input device which
	 * generated the event. You can pass NULL for the device if you want to move
	 * the cursor around without any input. */
	wlr_cursor_move(pointer->cursor, event->device, event->delta_x, event->delta_y);

	FlutterPointerEvent e = {};
	e.struct_size = sizeof(FlutterPointerEvent);
	e.phase = pointer->mouse_button_tracker.are_any_buttons_pressed() ? kMove : kHover;
	e.timestamp = current_time_microseconds();
	e.x = pointer->cursor->x * server->output->wlr_output->scale;
	e.y = pointer->cursor->y * server->output->wlr_output->scale;
	e.device_kind = kFlutterPointerDeviceKindMouse;
	e.buttons = pointer->mouse_button_tracker.get_flutter_mouse_state();

	server->embedder_state->send_pointer_event(e);
}

void server_cursor_motion_absolute(wl_listener* listener, void* data) {
	ZenithPointer* pointer = wl_container_of(listener, pointer, cursor_motion_absolute);
	ZenithServer* server = pointer->server;
	auto* event = static_cast<wlr_event_pointer_motion_absolute*>(data);

	if (server->output == nullptr) {
		return;
	}

	pointer->set_visible(true);

	wlr_cursor_warp_absolute(pointer->cursor, event->device, event->x, event->y);

	FlutterPointerEvent e = {};
	e.struct_size = sizeof(FlutterPointerEvent);
	e.phase = pointer->mouse_button_tracker.are_any_buttons_pressed() ? kMove : kHover;
	e.timestamp = current_time_microseconds();

	// Map from [0, 1] to [output_width, output_height].
	e.x = pointer->cursor->x * server->output->wlr_output->scale;
	e.y = pointer->cursor->y * server->output->wlr_output->scale;
	e.device_kind = kFlutterPointerDeviceKindMouse;
	e.buttons = pointer->mouse_button_tracker.get_flutter_mouse_state();

	server->embedder_state->send_pointer_event(e);
}

void server_cursor_button(wl_listener* listener, void* data) {
	ZenithPointer* pointer = wl_container_of(listener, pointer, cursor_button);
	ZenithServer* server = pointer->server;
	auto* event = static_cast<wlr_event_pointer_button*>(data);

	if (server->output == nullptr) {
		return;
	}

	pointer->set_visible(true);

	FlutterPointerEvent e = {};
	e.struct_size = sizeof(FlutterPointerEvent);

	if (event->state == WLR_BUTTON_RELEASED) {
		pointer->mouse_button_tracker.release_button(event->button);
		e.phase = pointer->mouse_button_tracker.are_any_buttons_pressed() ? kMove : kUp;
	} else {
		bool are_any_buttons_pressed = pointer->mouse_button_tracker.are_any_buttons_pressed();
		pointer->mouse_button_tracker.press_button(event->button);
		e.phase = are_any_buttons_pressed ? kMove : kDown;
	}

	e.timestamp = current_time_microseconds();
	e.x = pointer->cursor->x * server->output->wlr_output->scale;
	e.y = pointer->cursor->y * server->output->wlr_output->scale;
	e.device_kind = kFlutterPointerDeviceKindMouse;
	e.buttons = pointer->mouse_button_tracker.get_flutter_mouse_state();

	server->embedder_state->send_pointer_event(e);
}

void server_cursor_axis(wl_listener* listener, void* data) {
	ZenithPointer* pointer = wl_container_of(listener, pointer, cursor_axis);
	ZenithServer* server = pointer->server;
	auto* event = static_cast<wlr_event_pointer_axis*>(data);

	if (server->output == nullptr) {
		return;
	}

	pointer->set_visible(true);

	/* Notify the client with pointer focus of the axis event. */
	wlr_seat_pointer_notify_axis(server->seat,
	                             event->time_msec, event->orientation, event->delta,
	                             event->delta_discrete, event->source);

	bool are_any_buttons_pressed = pointer->mouse_button_tracker.are_any_buttons_pressed();

	FlutterPointerEvent e = {};
	e.struct_size = sizeof(FlutterPointerEvent);
	e.phase = are_any_buttons_pressed ? kMove : kDown;
	e.timestamp = current_time_microseconds();
	e.x = pointer->cursor->x * server->output->wlr_output->scale;
	e.y = pointer->cursor->y * server->output->wlr_output->scale;
	e.device_kind = kFlutterPointerDeviceKindMouse;
	e.buttons = pointer->mouse_button_tracker.get_flutter_mouse_state();
	e.signal_kind = kFlutterPointerSignalKindScroll;
	switch (event->orientation) {
		case WLR_AXIS_ORIENTATION_VERTICAL:
			e.scroll_delta_y = event->delta;
			break;
		case WLR_AXIS_ORIENTATION_HORIZONTAL:
			e.scroll_delta_x = event->delta;
			break;
	}
	server->embedder_state->send_pointer_event(e);
}

void server_cursor_frame(wl_listener* listener, void* data) {
	/* Notify the client with pointer focus of the frame event. */
	wlr_seat_pointer_notify_frame(ZenithServer::instance()->seat);
}
