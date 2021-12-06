#include <iostream>
#include "output_callbacks.hpp"
#include "embedder.h"
#include "zenith_structs.hpp"
#include "flutter_callbacks.hpp"
#include "platform_channels/event_channel.h"
#include "platform_methods.hpp"
#include "create_shared_egl_context.hpp"
#include <src/platform_channels/event_stream_handler_functions.h>

extern "C" {
#include <semaphore.h>
#include <malloc.h>
#include <pthread.h>
#define static
#include <wayland-util.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/types/wlr_surface.h>
#include <wlr/types/wlr_xdg_shell.h>
#undef static
}

void server_new_output(wl_listener* listener, void* data) {
	ZenithServer* server = wl_container_of(listener, server, new_output);
	auto* wlr_output = static_cast<struct wlr_output*>(data);

	if (server->output != nullptr) {
		// Allow only one output for the time being.
		return;
	}

	if (!wl_list_empty(&wlr_output->modes)) {
		// Set the preferred resolution and refresh rate of the monitor which will probably be the highest one.
		wlr_output_enable(wlr_output, true);
		wlr_output_mode* mode = wlr_output_preferred_mode(wlr_output);
		wlr_output_set_mode(wlr_output, mode);

		if (!wlr_output_commit(wlr_output)) {
			return;
		}
	}

	// Allocates and configures our state for this output.

	auto* output = new ZenithOutput(BinaryMessenger(nullptr), IncomingMessageDispatcher(nullptr));
//	auto* output = static_cast<ZenithOutput*>(calloc(1, sizeof(ZenithOutput)));
	output->server = server;
	server->output = output;

	output->wlr_output = wlr_output;

	pthread_mutex_init(&output->baton_mutex, nullptr);
	sem_init(&output->vsync_semaphore, 0, 0);

	output->frame_listener.notify = output_frame;
	wl_signal_add(&wlr_output->events.frame, &output->frame_listener);

	wlr_output_layout_add_auto(server->output_layout, wlr_output);

	int width, height;
	wlr_output_effective_resolution(output->wlr_output, &width, &height);

	wlr_egl* egl = wlr_gles2_renderer_get_egl(output->server->renderer);

	wlr_egl_make_current(egl);
	output->flutter_gl_context = create_shared_egl_context(egl);
	output->flutter_resource_gl_context = create_shared_egl_context(egl);
	wlr_egl_unset_current(egl);

	// FBOs cannot be shared between GL contexts. Since these FBOs will be used by a Flutter thread, create these
	// resources using the Flutter's context.
	wlr_egl_make_current(output->flutter_gl_context);
	output->fix_y_flip = fix_y_flip_init_state(width, height);
	output->present_fbo = std::make_unique<SurfaceFramebuffer>(width, height);
	wlr_egl_unset_current(output->flutter_gl_context);

	wlr_egl_make_current(egl);
	output->render_to_texture_shader = std::make_unique<RenderToTextureShader>();
	// The Flutter engine will use the wlr renderer and its egl context on the render thread, therefore it must be
	// unset in this thread because a context cannot be bound to multiple threads at once.

	output->surface_framebuffers = std::map<wlr_texture*, std::unique_ptr<SurfaceFramebuffer>>();

	// Create the Flutter engine for this output.
	FlutterEngine engine = run_flutter(output);
	output->engine = engine;
	output->messenger = BinaryMessenger(engine);
	output->message_dispatcher = IncomingMessageDispatcher(&output->messenger);
	output->messenger.SetMessageDispatcher(&output->message_dispatcher);

	auto& codec = flutter::StandardMethodCodec::GetInstance();

	output->platform_method_channel = std::make_unique<flutter::MethodChannel<>>(
		  &output->messenger, "platform", &codec);

	output->platform_method_channel->SetMethodCallHandler(
		  [output](const flutter::MethodCall<>& call, std::unique_ptr<flutter::MethodResult<>> result) {
			  if (call.method_name() == "activate_window") {
				  activate_window(output, call, std::move(result));
			  } else if (call.method_name() == "pointer_hover") {
				  pointer_hover(output, call, std::move(result));
			  } else if (call.method_name() == "close_window") {
				  close_window(output, call, std::move(result));
			  } else {
				  result->Error("method_does_not_exist", "Method " + call.method_name() + " does not exist");
			  }
		  });

	FlutterWindowMetricsEvent window_metrics = {};
	window_metrics.struct_size = sizeof(FlutterWindowMetricsEvent);
	window_metrics.width = width;
	window_metrics.height = height;
	window_metrics.pixel_ratio = 1.0;

	FlutterEngineSendWindowMetricsEvent(engine, &window_metrics);
}

void output_frame(wl_listener* listener, void* data) {
	ZenithOutput* output = wl_container_of(listener, output, frame_listener);

	wlr_egl* egl = wlr_gles2_renderer_get_egl(output->server->renderer);
	wlr_egl_make_current(egl);

	for (auto* view: output->server->views) {
		if (!view->mapped) {
			/* An unmapped view should not be rendered. */
			continue;
		}
		wlr_texture* texture = wlr_surface_get_texture(view->xdg_surface->surface);

		output->surface_framebuffers_mutex.lock();

		auto surface_framebuffer_it = output->surface_framebuffers.find(texture);
		if (surface_framebuffer_it == output->surface_framebuffers.end()) {
			auto inserted_pair = output->surface_framebuffers.insert(
				  std::pair<wlr_texture*, std::unique_ptr<SurfaceFramebuffer>>(
						texture,
						std::make_unique<SurfaceFramebuffer>(texture->width, texture->height)
				  )
			);
			surface_framebuffer_it = inserted_pair.first;
		}

		wlr_gles2_texture_attribs attribs{};
		wlr_gles2_texture_get_attribs(texture, &attribs);

		output->render_to_texture_shader->render(attribs.tex, texture->width, texture->height,
		                                         surface_framebuffer_it->second->framebuffer);
		output->surface_framebuffers_mutex.unlock();

		FlutterEngineMarkExternalTextureFrameAvailable(output->engine, (int64_t) texture);

		timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		wlr_surface_send_frame_done(view->xdg_surface->surface, &now);
	}

	intptr_t baton;
	pthread_mutex_lock(&output->baton_mutex);
	if (output->new_baton) {
		baton = output->baton;
		output->new_baton = false;

		uint64_t start = FlutterEngineGetCurrentTime();
		FlutterEngineOnVsync(output->engine, baton, start, start + 1'000'000'000ull / 60);
	}
	pthread_mutex_unlock(&output->baton_mutex);

	if (!wlr_output_attach_render(output->wlr_output, nullptr)) {
		return;
	}

	int width, height;
	wlr_output_effective_resolution(output->wlr_output, &width, &height);

	wlr_renderer_begin(output->server->renderer, width, height);

	uint32_t output_fbo = wlr_gles2_renderer_get_current_fbo(output->server->renderer);

	output->flip_mutex.lock();
	output->render_to_texture_shader->render(output->present_fbo->texture, width, height, output_fbo);
	output->flip_mutex.unlock();

	wlr_renderer_end(output->server->renderer);
	wlr_output_commit(output->wlr_output);

	// Execute all platform tasks while waiting for the next frame event.
	wl_event_loop_add_idle(wl_display_get_event_loop(output->server->display), flutter_execute_platform_tasks,
	                       nullptr);
}
