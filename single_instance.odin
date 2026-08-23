package main

import "base:runtime"
import "core:os"
import "core:strings"
import linux "core:sys/linux"

LOCK_PATH_SUFFIX :: "/vima.lock"
SOCKET_PATH_SUFFIX :: "/vima.sock"

Instance_Lock :: struct {
	file: ^os.File,
}

Toggle_Server :: struct {
	socket: linux.Fd,
	path:   string,
	active: bool,
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
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	runtime_dir, found := os.lookup_env("XDG_RUNTIME_DIR", context.temp_allocator)
	if !found {
		return "", false
	}
	return strings.concatenate({runtime_dir, SOCKET_PATH_SUFFIX}, allocator), true
}

start_toggle_server :: proc(allocator := context.allocator) -> (Toggle_Server, bool) {
	sock_path, ok := get_socket_path(allocator)
	if !ok || len(sock_path) == 0 || len(sock_path) >= 108 {
		if ok {
			delete(sock_path, allocator)
		}
		return {}, false
	}

	listen_socket, socket_error := linux.socket(
		.UNIX,
		.STREAM,
		{.CLOEXEC, .NONBLOCK},
		cast(linux.Protocol)0,
	)
	if socket_error != .NONE {
		delete(sock_path, allocator)
		return {}, false
	}

	// The instance lock guarantees that no live Vima process owns this path.
	// Remove a socket left behind by an unclean exit before binding.
	_ = os.remove(sock_path)

	address := linux.Sock_Addr_Un {
		sun_family = .UNIX,
	}
	copy(address.sun_path[:], transmute([]u8)sock_path)

	if linux.bind(listen_socket, &address) != .NONE || linux.listen(listen_socket, 1) != .NONE {
		linux.close(listen_socket)
		_ = os.remove(sock_path)
		delete(sock_path, allocator)
		return {}, false
	}

	return Toggle_Server{socket = listen_socket, path = sock_path, active = true}, true
}

stop_toggle_server :: proc(server: ^Toggle_Server, allocator := context.allocator) {
	if !server.active {
		return
	}

	linux.close(server.socket)
	_ = os.remove(server.path)
	delete(server.path, allocator)
	server^ = {}
}

poll_toggle_signal :: proc(server: ^Toggle_Server) -> bool {
	if !server.active {
		return false
	}

	address: linux.Sock_Addr_Un
	connection, accept_error := linux.accept(server.socket, &address, {.CLOEXEC})
	if accept_error != .NONE {
		return false
	}
	defer linux.close(connection)

	signal: [1]u8
	bytes_received, receive_error := linux.recv(connection, signal[:], {})
	return receive_error == .NONE && bytes_received == len(signal) && signal[0] == 1
}

send_toggle_signal :: proc() -> bool {
	sock_path, ok := get_socket_path()
	if !ok {
		return false
	}
	defer delete(sock_path)

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
