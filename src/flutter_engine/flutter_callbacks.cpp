#include "flutter_callbacks.hpp"
#include "flutter_engine_state.hpp"
#include "server.hpp"

extern "C" {
#define static
#include <wlr/render/egl.h>
#include <wlr/render/gles2.h>
#include <wlr/types/wlr_output.h>
#undef static
}

#include <GL/gl.h>
#include <cassert>
#include <iostream>

bool flutter_make_current(void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);
	return wlr_egl_make_current(state->flutter_gl_context);
}

bool flutter_clear_current(void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);
	return wlr_egl_unset_current(state->flutter_gl_context);
}

static size_t i = 0;

bool flutter_present(void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);

	for (auto& fb: state->framebuffers_in_use) {
		fb->stop_reading();
	}
	state->framebuffers_in_use.clear();

	std::scoped_lock lock(state->present_fbo->mutex);

	Framebuffer& fb = state->present_fbo->start_writing();

	render_to_fbo(&state->fix_y_flip, fb.framebuffer);
	// TODO: maybe it's better to use a fence instead
	glFinish(); // Don't remove this line!

	state->present_fbo->stop_writing();

	std::cout << "i = " << i << std::endl;
	i = 0;

	return true;
}

uint32_t flutter_fbo_callback(void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);
	return state->fix_y_flip.offscreen_framebuffer;
}

void flutter_vsync_callback(void* userdata, intptr_t baton) {
	auto* state = static_cast<FlutterEngineState*>(userdata);

	std::scoped_lock lock(state->baton_mutex);

	assert(state->new_baton == false);
	state->new_baton = true;
	state->baton = baton;
}

bool flutter_gl_external_texture_frame_callback(void* userdata, int64_t view_id, size_t width, size_t height,
                                                FlutterOpenGLTexture* texture_out) {
	auto* state = static_cast<FlutterEngineState*>(userdata);
	ZenithServer* server = state->output->server;

	std::shared_ptr<SurfaceFramebuffer> surface_framebuffer;
	{
		std::scoped_lock lock(server->surface_framebuffers_mutex);

		auto it = server->surface_framebuffers.find(view_id);
		if (it == server->surface_framebuffers.end()) {
			// This function could be called any time so we better check if the framebuffer still exists.
			// Asynchronicity can be a pain sometimes.
			return false;
		}
		surface_framebuffer = it->second;
	}

	std::scoped_lock lock(surface_framebuffer->mutex);


	Framebuffer& fb = surface_framebuffer->start_reading();

	texture_out->target = GL_TEXTURE_2D;
	texture_out->format = GL_RGBA8;
	texture_out->name = fb.texture;

	// Make sure the framebuffer doesn't get destroyed at the end of this function if this
	// shared_ptr happens to be the only copy left. We don't want the destructor to run and delete
	// the texture because Flutter is going to render it later. We can safely clear this list
	// after all the rendering is done.
	state->framebuffers_in_use.push_back(surface_framebuffer);
	return true;
}

void flutter_platform_message_callback(const FlutterPlatformMessage* message, void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);

	if (message->struct_size != sizeof(FlutterPlatformMessage)) {
		std::cerr << "ERROR: Invalid message size received. Expected: "
		          << sizeof(FlutterPlatformMessage) << " but received "
		          << message->struct_size;
		return;
	}

	state->message_dispatcher.HandleMessage(*message, [] {}, [] {});
}

bool flutter_make_resource_current(void* userdata) {
	auto* state = static_cast<FlutterEngineState*>(userdata);
	return wlr_egl_make_current(state->flutter_resource_gl_context);
}

int flutter_execute_expired_tasks_timer(void* data) {
	auto* state = static_cast<FlutterEngineState*>(data);

	state->platform_task_runner.execute_expired_tasks();
	// I would have preferred to have the delay represented in nanoseconds because I could reschedule
	// an update at exactly the right time for the earliest task to be executed, but we'll just reschedule
	// as fast as possible, every millisecond. This shouldn't be heavy for a CPU anyway.
	wl_event_source_timer_update(state->platform_task_runner_timer, 1);
	return 0;
}