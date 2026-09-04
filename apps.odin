package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

Installed_App :: struct {
	name:         cstring,
	search_index: string,
	generic_name: cstring,
	exec:         cstring,
	icon:         cstring,
	description:  cstring,
}

App_Error :: struct {
	message: string,
}

get_installed_apps_info :: proc() -> ([dynamic]Installed_App, App_Error) {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	combined_apps_dir := make([dynamic]string, context.allocator)
	defer {
		for dir in combined_apps_dir {
			delete(dir)
		}

		delete(combined_apps_dir)
	}

	user_apps_dir := get_user_apps_dir()
	if len(user_apps_dir) > 0 {
		append(&combined_apps_dir, user_apps_dir)
	}

	system_apps_dirs := get_system_apps_dirs()
	append(&combined_apps_dir, ..system_apps_dirs[:])
	delete(system_apps_dirs)

	apps := get_apps_info_from_dirs(combined_apps_dir[:])
	slice.sort_by(apps[:], proc(a: Installed_App, b: Installed_App) -> bool {
		return a.name < b.name
	})

	return apps, {}
}

get_apps_info_from_dirs :: proc(
	apps_dirs: []string,
	allocator := context.allocator,
) -> [dynamic]Installed_App {
	apps := make([dynamic]Installed_App, allocator)
	for dir, _ in apps_dirs {
		files, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil {
			continue
		}

		for file, _ in files {
			if !strings.ends_with(file.name, ".desktop") {
				continue
			}

			app := parse_desktop_file(file.fullpath)
			append(&apps, app)
		}
	}

	return apps
}

parse_desktop_file :: proc(file_path: string, allocator := context.allocator) -> Installed_App {
	data, err := os.read_entire_file_from_path(file_path, context.temp_allocator)
	if err != nil {
		return Installed_App{}
	}

	content := string(data)
	lines := strings.split_lines(content, context.temp_allocator)

	app := Installed_App{}
	for raw_line in lines {
		line := strings.trim(raw_line, " \t\r\n")
		if len(line) == 0 || line[0] == '#' {
			continue
		}

		if strings.contains(line, "[Desktop Entry]") {
			continue
		}

		eq_index := strings.index(line, "=")
		if eq_index == -1 {
			continue
		}

		key := strings.trim(line[:eq_index], " \t\r\n")
		value := strings.trim(line[eq_index + 1:], " \t\r\n")

		switch key {
		case "Name":
			if app.name == nil {
				app.name = strings.clone_to_cstring(value, allocator)
				if app.search_index == "" {
					app.search_index = strings.to_lower(value, allocator)
				}
			}

		case "Exec":
			if app.exec == nil {
				app.exec = clean_exec_string(value)
			}

		case "Icon":
			if app.icon == nil {
				app.icon = strings.clone_to_cstring(value, allocator)
			}

		case "Comment":
			if app.description == nil {
				app.description = strings.clone_to_cstring(value, allocator)
			}

		case "GenericName":
			if app.generic_name == nil {
				app.generic_name = strings.clone_to_cstring(value, allocator)
			}
		}
	}

	return app
}

launch_app :: proc(exec: string) -> bool {
	argv := exec_to_argv(exec)
	defer {
		for a in argv do delete(a)
		delete(argv)
	}

	if len(argv) == 0 {
		return false
	}

	when ODIN_OS == .Linux {
		systemd_command := make([]string, len(argv) + 7)
		defer delete(systemd_command)

		systemd_command[0] = "systemd-run"
		systemd_command[1] = "--user"
		systemd_command[2] = "--collect"
		systemd_command[3] = "--quiet"
		systemd_command[4] = "--slice=app.slice"
		systemd_command[5] = "--property=ExitType=cgroup"
		systemd_command[6] = "--"
		copy(systemd_command[7:], argv)

		systemd_state, systemd_stdout, systemd_stderr, systemd_err := os.process_exec(
			os.Process_Desc{command = systemd_command},
			context.allocator,
		)
		defer delete(systemd_stdout)
		defer delete(systemd_stderr)
		if systemd_err == nil && systemd_state.success {
			return true
		}
	}

	desc := os.Process_Desc {
		command = argv,
	}

	_, err := os.process_start(desc)
	if err != nil {
		return false
	}

	return true
}

search_apps :: proc(
	apps: []Installed_App,
	query: string,
	allocator := context.allocator,
) -> [dynamic]int {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	result := make([dynamic]int, 0, len(apps), allocator)
	lower_query := strings.to_lower(query, context.temp_allocator)

	for app, index in apps {
		if app.search_index == "" {
			continue
		}

		if strings.contains(app.search_index, lower_query) {
			append(&result, index)
		}
	}

	return result
}

get_user_apps_dir :: proc(allocator := context.allocator) -> string {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	value, ok := os.lookup_env("XDG_DATA_HOME", context.temp_allocator)
	if !ok || value == "" {
		home := os.get_env("HOME", context.temp_allocator)
		if len(home) == 0 {
			return ""
		}
		return strings.concatenate({home, "/.local/share/applications"}, allocator)
	}

	return strings.concatenate({value, "/applications"}, allocator)
}

get_system_apps_dirs :: proc(allocator := context.allocator) -> []string {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	value, found := os.lookup_env("XDG_DATA_DIRS", context.temp_allocator)
	if !found || len(value) == 0 {
		value = "/usr/local/share:/usr/share"
	}

	dirs := strings.split(value, ":", context.temp_allocator)
	apps_dirs := make([]string, len(dirs), allocator)
	for dir, i in dirs {
		if len(dir) == 0 {
			continue
		}
		apps_dirs[i] = strings.concatenate({dir, "/applications"}, allocator)
	}

	return apps_dirs
}

clean_exec_string :: proc(exec: string, allocator := context.allocator) -> cstring {
	tokens := strings.split(exec, " ")
	defer delete(tokens)

	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	first := true
	for token in tokens {
		if token == "%f" ||
		   token == "%F" ||
		   token == "%u" ||
		   token == "%U" ||
		   token == "%i" ||
		   token == "%c" ||
		   token == "%k" ||
		   token == "%v" ||
		   token == "%m" {
			continue
		}

		if !first {
			strings.write_byte(&sb, ' ')
		}

		strings.write_string(&sb, token)
		first = false
	}

	temp := strings.clone(strings.to_string(sb), context.allocator)
	defer delete(temp)

	return strings.clone_to_cstring(temp, allocator)
}

exec_to_argv :: proc(exec: string) -> []string {
	parts := strings.split(exec, " ")
	defer delete(parts)

	argv := make([]string, len(parts))
	for p, i in parts {
		argv[i] = strings.clone(p)
	}

	return argv
}

destroy_installed_apps :: proc(apps: [dynamic]Installed_App, allocator := context.allocator) {
	for app in apps {
		if app.name != nil {
			delete(app.name, allocator)
		}

		if app.search_index != "" {
			delete(app.search_index, allocator)
		}

		if app.exec != nil {
			delete(app.exec, allocator)
		}

		if app.generic_name != nil {
			delete(app.generic_name, allocator)
		}

		if app.icon != nil {
			delete(app.icon, allocator)
		}

		if app.description != nil {
			delete(app.description, allocator)
		}
	}

	delete(apps)
}
