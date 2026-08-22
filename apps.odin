package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

Installed_App :: struct {
	name:        cstring,
	exec:        cstring,
	icon:        cstring,
	description: cstring,
}

App_Error :: struct {
	message: string,
}

get_system_wide_apps :: proc() -> ([dynamic]Installed_App, App_Error) {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	value, found := os.lookup_env("XDG_DATA_DIRS", context.temp_allocator)
	if !found {
		return {}, App_Error{message = "XDG_DATA_DIRS not found"}
	}

	dirs := strings.split(value, ":", context.temp_allocator)

	apps_dirs := make([]string, len(dirs), context.temp_allocator)
	for dir, i in dirs {
		apps_dirs[i] = strings.concatenate({dir, "/applications"}, context.temp_allocator)
	}

	apps := make([dynamic]Installed_App, context.allocator)
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

	return apps, {}
}


parse_desktop_file :: proc(file_path: string) -> Installed_App {
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
				app.name = strings.clone_to_cstring(value, context.allocator)
			}

		case "Exec":
			if app.exec == nil {
				app.exec = strings.clone_to_cstring(value, context.allocator)
			}

		case "Icon":
			if app.icon == nil {
				app.icon = strings.clone_to_cstring(value, context.allocator)
			}

		case "Comment":
			if app.description == nil {
				app.description = strings.clone_to_cstring(value, context.allocator)
			}
		}
	}

	return app
}

destroy_installed_apps :: proc(apps: [dynamic]Installed_App) {
	for app in apps {
		if app.name != nil {
			delete(app.name)
		}
		if app.exec != nil {
			delete(app.exec)
		}
		if app.icon != nil {
			delete(app.icon)
		}
		if app.description != nil {
			delete(app.description)
		}
	}

	delete(apps)
}
