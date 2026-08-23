package main

main :: proc() {
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
