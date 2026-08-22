package main

import "base:runtime"
import "core:os"
import "core:strings"

ICON_FALLBACK_NAME :: "application-x-executable"

active_icon_theme :: proc(allocator := context.allocator) -> string {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	home, found := os.lookup_env("HOME", context.temp_allocator)
	if !found {
		return strings.clone("hicolor", allocator)
	}

	config_home, has_config_home := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator)
	config_path := strings.concatenate({home, "/.config/kdeglobals"}, context.temp_allocator)
	if has_config_home && len(config_home) > 0 {
		config_path = strings.concatenate({config_home, "/kdeglobals"}, context.temp_allocator)
	}

	data, err := os.read_entire_file_from_path(config_path, context.temp_allocator)
	if err != nil {
		return strings.clone("hicolor", allocator)
	}

	in_icons_section := false
	content := string(data)
	for raw_line in strings.split_lines_iterator(&content) {
		line := strings.trim(raw_line, " \t\r\n")
		if strings.starts_with(line, "[") {
			in_icons_section = line == "[Icons]"
			continue
		}
		if in_icons_section && strings.starts_with(line, "Theme=") {
			theme := strings.trim(strings.trim_prefix(line, "Theme="), " \t\r\n")
			if len(theme) > 0 {
				return strings.clone(theme, allocator)
			}
		}
	}

	return strings.clone("hicolor", allocator)
}

resolve_icon_path :: proc(
	icon_name: cstring,
	theme: string,
	allocator := context.allocator,
) -> cstring {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
	if icon_name == nil || len(icon_name) == 0 {
		return nil
	}

	name := string(icon_name)
	if strings.starts_with(name, "/") {
		if os.exists(name) {
			return strings.clone_to_cstring(name, allocator)
		}
		return nil
	}

	roots := make([dynamic]string, 0, 6, context.temp_allocator)
	home, has_home := os.lookup_env("HOME", context.temp_allocator)
	if has_home {
		append(&roots, strings.concatenate({home, "/.local/share/icons"}, context.temp_allocator))
		append(&roots, strings.concatenate({home, "/.icons"}, context.temp_allocator))
	}

	data_dirs_value, has_data_dirs := os.lookup_env("XDG_DATA_DIRS", context.temp_allocator)
	if !has_data_dirs || len(data_dirs_value) == 0 {
		data_dirs_value = "/usr/local/share:/usr/share"
	}
	data_dirs_for_roots := data_dirs_value
	for data_dir in strings.split_iterator(&data_dirs_for_roots, ":") {
		if len(data_dir) > 0 {
			append(&roots, strings.concatenate({data_dir, "/icons"}, context.temp_allocator))
		}
	}

	themes := [3]string{theme, "breeze", "hicolor"}
	layouts := [?]string {
		"apps/32",
		"32x32/apps",
		"apps/48",
		"48x48/apps",
		"apps/64",
		"64x64/apps",
		"apps/scalable",
		"scalable/apps",
		"128x128/apps",
		"256x256/apps",
		"512x512/apps",
		"preferences/32",
		"32x32/preferences",
		"preferences/scalable",
		"scalable/preferences",
		"categories/32",
		"32x32/categories",
		"categories/scalable",
		"scalable/categories",
		"devices/32",
		"32x32/devices",
		"devices/scalable",
		"scalable/devices",
		"actions/32",
		"32x32/actions",
		"places/32",
		"32x32/places",
		"status/32",
		"32x32/status",
		"mimetypes/32",
		"32x32/mimetypes",
	}
	extensions := [?]string{".png", ".svg", ".svgz", ".xpm"}
	has_extension := strings.ends_with(name, ".png") ||
		strings.ends_with(name, ".svg") ||
		strings.ends_with(name, ".svgz") ||
		strings.ends_with(name, ".xpm")

	for theme_name in themes {
		if len(theme_name) == 0 {
			continue
		}
		for root in roots {
			for layout in layouts {
				base := strings.concatenate(
					{root, "/", theme_name, "/", layout, "/", name},
					context.temp_allocator,
				)
				if has_extension && os.exists(base) {
					return strings.clone_to_cstring(base, allocator)
				}
				if !has_extension {
					for extension in extensions {
						candidate := strings.concatenate({base, extension}, context.temp_allocator)
						if os.exists(candidate) {
							return strings.clone_to_cstring(candidate, allocator)
						}
					}
				}
			}
		}
	}

	// Legacy icon files may be installed outside a named theme.
	data_dirs_for_pixmaps := data_dirs_value
	for data_dir in strings.split_iterator(&data_dirs_for_pixmaps, ":") {
		if len(data_dir) == 0 {
			continue
		}
		base := strings.concatenate({data_dir, "/pixmaps/", name}, context.temp_allocator)
		if has_extension && os.exists(base) {
			return strings.clone_to_cstring(base, allocator)
		}
		if !has_extension {
			for extension in extensions {
				candidate := strings.concatenate({base, extension}, context.temp_allocator)
				if os.exists(candidate) {
					return strings.clone_to_cstring(candidate, allocator)
				}
			}
		}
	}

	return nil
}
