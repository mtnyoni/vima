package main

import "core:c"

when ODIN_OS == .Linux {
	foreign import wayland_client {"system:wayland-client", "build/native/libvima-wayland.a"}

	foreign wayland_client {
		vima_layer_shell_supported :: proc() -> c.int ---
		vima_layer_shell_attach :: proc(display, surface: rawptr) -> rawptr ---
		vima_layer_shell_destroy :: proc(state: rawptr) ---
		vima_layer_shell_width :: proc(state: rawptr) -> u32 ---
		vima_layer_shell_height :: proc(state: rawptr) -> u32 ---
		vima_layer_shell_closed :: proc(state: rawptr) -> c.int ---
	}
}
