#include "vima_layer_shell.h"

#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

struct VimaLayerShell {
  struct wl_display *display;
  struct zwlr_layer_shell_v1 *shell;
  struct zwlr_layer_surface_v1 *surface;
  uint32_t width;
  uint32_t height;
  int configured;
  int closed;
};

struct RegistryState {
  struct zwlr_layer_shell_v1 *shell;
};

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
  struct RegistryState *state = data;
  if (strcmp(interface, zwlr_layer_shell_v1_interface.name) != 0) {
    return;
  }

  uint32_t bind_version = version < 5 ? version : 5;
  state->shell = wl_registry_bind(registry, name,
                                  &zwlr_layer_shell_v1_interface, bind_version);
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

static struct zwlr_layer_shell_v1 *
bind_layer_shell(struct wl_display *display) {
  struct RegistryState state = {0};
  struct wl_registry *registry = wl_display_get_registry(display);
  if (registry == NULL) {
    return NULL;
  }

  wl_registry_add_listener(registry, &registry_listener, &state);
  if (wl_display_roundtrip(display) < 0) {
    wl_registry_destroy(registry);
    return NULL;
  }

  wl_registry_destroy(registry);
  return state.shell;
}

int vima_layer_shell_supported(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (display == NULL) {
    return 0;
  }

  struct zwlr_layer_shell_v1 *shell = bind_layer_shell(display);
  int supported = shell != NULL;
  if (shell != NULL) {
    if (wl_proxy_get_version((struct wl_proxy *)shell) >= 3) {
      zwlr_layer_shell_v1_destroy(shell);
    } else {
      wl_proxy_destroy((struct wl_proxy *)shell);
    }
  }
  wl_display_disconnect(display);
  return supported;
}

static void layer_surface_configure(void *data,
                                    struct zwlr_layer_surface_v1 *surface,
                                    uint32_t serial, uint32_t width,
                                    uint32_t height) {
  VimaLayerShell *state = data;
  zwlr_layer_surface_v1_ack_configure(surface, serial);
  state->width = width;
  state->height = height;
  state->configured = width > 0 && height > 0;
}

static void layer_surface_closed(void *data,
                                 struct zwlr_layer_surface_v1 *surface) {
  (void)surface;
  VimaLayerShell *state = data;
  state->closed = 1;
}

static const struct zwlr_layer_surface_v1_listener layer_surface_listener = {
    .configure = layer_surface_configure,
    .closed = layer_surface_closed,
};

VimaLayerShell *vima_layer_shell_attach(void *display_pointer,
                                        void *surface_pointer) {
  if (display_pointer == NULL || surface_pointer == NULL) {
    return NULL;
  }

  VimaLayerShell *state = calloc(1, sizeof(*state));
  if (state == NULL) {
    return NULL;
  }

  state->display = display_pointer;
  state->shell = bind_layer_shell(state->display);
  if (state->shell == NULL) {
    free(state);
    return NULL;
  }

  state->surface = zwlr_layer_shell_v1_get_layer_surface(
      state->shell, surface_pointer, NULL, ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY,
      "vima");
  if (state->surface == NULL) {
    vima_layer_shell_destroy(state);
    return NULL;
  }

  zwlr_layer_surface_v1_add_listener(state->surface, &layer_surface_listener,
                                     state);
  zwlr_layer_surface_v1_set_anchor(state->surface,
                                   ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
                                       ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
  zwlr_layer_surface_v1_set_size(state->surface, 0, 0);
  // Respect areas reserved by panels so taskbar clicks pass through to them.
  // The remaining workspace stays covered and continues to dismiss on click.
  zwlr_layer_surface_v1_set_exclusive_zone(state->surface, 0);
  zwlr_layer_surface_v1_set_keyboard_interactivity(
      state->surface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_ON_DEMAND);
  wl_surface_commit(surface_pointer);

  for (int attempt = 0; attempt < 4 && !state->configured; ++attempt) {
    if (wl_display_roundtrip(state->display) < 0) {
      vima_layer_shell_destroy(state);
      return NULL;
    }
  }

  if (!state->configured) {
    vima_layer_shell_destroy(state);
    return NULL;
  }
  return state;
}

void vima_layer_shell_destroy(VimaLayerShell *state) {
  if (state == NULL) {
    return;
  }
  if (state->surface != NULL) {
    zwlr_layer_surface_v1_destroy(state->surface);
  }
  if (state->shell != NULL) {
    if (wl_proxy_get_version((struct wl_proxy *)state->shell) >= 3) {
      zwlr_layer_shell_v1_destroy(state->shell);
    } else {
      wl_proxy_destroy((struct wl_proxy *)state->shell);
    }
  }
  free(state);
}

uint32_t vima_layer_shell_width(const VimaLayerShell *state) {
  return state == NULL ? 0 : state->width;
}

uint32_t vima_layer_shell_height(const VimaLayerShell *state) {
  return state == NULL ? 0 : state->height;
}

int vima_layer_shell_closed(const VimaLayerShell *state) {
  return state == NULL ? 1 : state->closed;
}
