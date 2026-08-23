package main

import "core:fmt"
import "core:mem"


main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}

		mem.tracking_allocator_destroy(&track)
	}
	context.allocator = mem.tracking_allocator(&track)

	lock, acquired := acquire_instance_lock()
	if !acquired {
		// Another Vima is already running — signal it (via the socket/IPC
		// we discussed earlier) and exit immediately, don't build a second UI
		send_show_signal()
		return
	}
	defer release_instance_lock(&lock)

	main_window()
}
