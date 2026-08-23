package main

import "core:os"
import "core:strings"
import linux "core:sys/linux"

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

LOCK_PATH_SUFFIX :: "/vima.lock"
SOCKET_PATH_SUFFIX :: "/vima.sock"

Instance_Lock :: struct {
	file: ^os.File,
}

acquire_instance_lock :: proc() -> (Instance_Lock, bool) {
	runtime_dir, found := os.lookup_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if !found {
		return {}, false
	}

	lock_path := strings.concatenate({runtime_dir, LOCK_PATH_SUFFIX}, context.temp_allocator)

	file, err := os.open(lock_path, {.Read, .Write, .Create}, {.Read_User, .Write_User})
	if err != nil {
		return {}, false
	}

	lock_error := linux.flock(linux.Fd(os.fd(file)), {.EX, .NB})
	if lock_error != .NONE {
		os.close(file)
		return {}, false
	}

	return Instance_Lock{file = file}, true
}

release_instance_lock :: proc(lock: ^Instance_Lock) {
	if lock.file != nil {
		os.close(lock.file)
		lock.file = nil
	}
}


get_socket_path :: proc(allocator := context.allocator) -> (string, bool) {
	runtime_dir, found := os.lookup_env("XDG_RUNTIME_DIR", allocator)
	if !found {
		return "", false
	}
	return strings.concatenate({runtime_dir, SOCKET_PATH_SUFFIX}, allocator), true
}

send_show_signal :: proc() -> bool {
	sock_path, ok := get_socket_path(context.temp_allocator)
	if !ok {
		return false
	}

	// Linux sockaddr_un.sun_path has room for 107 path bytes plus its
	// terminating zero byte.
	if len(sock_path) == 0 || len(sock_path) >= 108 {
		return false
	}

	conn, socket_error := linux.socket(.UNIX, .STREAM, {.CLOEXEC}, cast(linux.Protocol)0)
	if socket_error != .NONE {
		return false
	}
	defer linux.close(conn)

	address := linux.Sock_Addr_Un {
		sun_family = .UNIX,
	}
	copy(address.sun_path[:], transmute([]u8)sock_path)

	connect_error := linux.connect(conn, &address)
	if connect_error != .NONE {
		return false // couldn't connect — maybe the other instance died between flock check and now
	}

	signal := [1]u8{1}
	bytes_sent, send_error := linux.send(conn, signal[:], {})
	return send_error == .NONE && bytes_sent == len(signal)
}
