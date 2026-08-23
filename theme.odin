package main

import "base:runtime"
import "core:os"
import "core:strconv"
import "core:strings"

import sdl "vendor:sdl3"

Color :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

UI_Theme :: struct {
	app:           Color,
	input_border:  Color,
	window_border: Color,
	text:          Color,
	subtext:       Color,
	hover:         Color,
	selected:      Color,
	selected_text: Color,
	separator:     Color,
	shadow:        Color,
}

// Catppuccin Frappé fallback.
DARK_UI_THEME :: UI_Theme {
	app           = {35, 38, 52, 255},
	input_border  = {81, 87, 109, 255},
	window_border = {98, 104, 128, 255},
	text          = {198, 208, 245, 255},
	subtext       = {165, 173, 206, 255},
	hover         = {81, 87, 109, 255},
	selected      = {65, 69, 89, 255},
	selected_text = {198, 208, 245, 255},
	separator     = {41, 44, 60, 255},
	shadow        = {35, 38, 52, 90},
}

// Catppuccin Latte fallback.
LIGHT_UI_THEME :: UI_Theme {
	app           = {239, 241, 245, 255},
	input_border  = {188, 192, 204, 255},
	window_border = {172, 176, 190, 255},
	text          = {76, 79, 105, 255},
	subtext       = {108, 111, 133, 255},
	hover         = {188, 192, 204, 255},
	selected      = {204, 208, 218, 255},
	selected_text = {76, 79, 105, 255},
	separator     = {230, 233, 239, 255},
	shadow        = {76, 79, 105, 55},
}

app_color: Color = DARK_UI_THEME.app
input_border_color: Color = DARK_UI_THEME.input_border
window_border_color: Color = DARK_UI_THEME.window_border
text_color: Color = DARK_UI_THEME.text
subtext_color: Color = DARK_UI_THEME.subtext
hover_color: Color = DARK_UI_THEME.hover
selected_color: Color = DARK_UI_THEME.selected
selected_text_color: Color = DARK_UI_THEME.selected_text
separator_color: Color = DARK_UI_THEME.separator
shadow_color: Color = DARK_UI_THEME.shadow

apply_system_theme :: proc() {
	fallback := DARK_UI_THEME
	if sdl.GetSystemTheme() == .LIGHT {
		fallback = LIGHT_UI_THEME
	}

	apply_ui_theme(load_os_ui_theme(fallback))
}

load_os_ui_theme :: proc(fallback: UI_Theme) -> UI_Theme {
	theme := fallback

	when ODIN_OS == .Linux {
		load_kde_ui_theme(&theme)
	}

	return theme
}

load_kde_ui_theme :: proc(theme: ^UI_Theme) {
	_temp_guard, _ := runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	current_desktop, has_current_desktop := os.lookup_env(
		"XDG_CURRENT_DESKTOP",
		context.temp_allocator,
	)
	if has_current_desktop {
		desktop_name := strings.to_lower(current_desktop, context.temp_allocator)
		if !strings.contains(desktop_name, "kde") && !strings.contains(desktop_name, "plasma") {
			return
		}
	}

	config_home, has_config_home := os.lookup_env("XDG_CONFIG_HOME", context.temp_allocator)
	config_path: string
	if has_config_home && len(config_home) > 0 {
		config_path = strings.concatenate({config_home, "/kdeglobals"}, context.temp_allocator)
	} else {
		home, has_home := os.lookup_env("HOME", context.temp_allocator)
		if !has_home || len(home) == 0 {
			return
		}
		config_path = strings.concatenate({home, "/.config/kdeglobals"}, context.temp_allocator)
	}

	data, err := os.read_entire_file_from_path(config_path, context.temp_allocator)
	if err != nil {
		return
	}

	section := ""
	content := string(data)
	found_system_color := false
	for raw_line in strings.split_lines_iterator(&content) {
		line := strings.trim(raw_line, " \t\r\n")
		if len(line) == 0 || line[0] == '#' {
			continue
		}

		if strings.starts_with(line, "[") && strings.ends_with(line, "]") {
			section = line[1:len(line) - 1]
			continue
		}

		equals_index := strings.index(line, "=")
		if equals_index < 0 {
			continue
		}

		key := strings.trim(line[:equals_index], " \t")
		value := strings.trim(line[equals_index + 1:], " \t")
		color, valid := parse_theme_color(value)
		if !valid {
			continue
		}

		switch section {
		case "Colors:Window":
			switch key {
			case "BackgroundNormal":
				theme.app = color
				found_system_color = true

			case "ForegroundNormal":
				theme.text = color
				found_system_color = true

			case "ForegroundInactive":
				theme.subtext = color
				found_system_color = true

			case "DecorationFocus":
				theme.input_border = color
				found_system_color = true
			}

		case "Colors:View":
			if key == "BackgroundNormal" {
				theme.separator = color
				found_system_color = true
			}

		case "Colors:Selection":
			switch key {
			case "BackgroundNormal":
				theme.selected = color
				found_system_color = true
			case "ForegroundNormal":
				theme.selected_text = color
				found_system_color = true
			}

		case "Colors:Button":
			if key == "BackgroundNormal" {
				theme.window_border = color
				theme.hover = color
				found_system_color = true
			}
		}
	}

	if found_system_color {
		theme.shadow = {theme.text.r, theme.text.g, theme.text.b, 55}
	}
}

parse_theme_color :: proc(value: string) -> (Color, bool) {
	components: [3]u8
	component_count := 0
	remaining := value
	for raw_component in strings.split_by_byte_iterator(&remaining, ',') {
		if component_count == len(components) {
			break
		}

		component, ok := strconv.parse_i64(strings.trim_space(raw_component))
		if !ok || component < 0 || component > 255 {
			return {}, false
		}
		components[component_count] = u8(component)
		component_count += 1
	}

	if component_count != len(components) {
		return {}, false
	}

	return {components[0], components[1], components[2], 255}, true
}

apply_ui_theme :: proc(theme: UI_Theme) {
	app_color = theme.app
	input_border_color = theme.input_border
	window_border_color = theme.window_border
	text_color = theme.text
	subtext_color = theme.subtext
	hover_color = theme.hover
	selected_color = theme.selected
	selected_text_color = theme.selected_text
	separator_color = theme.separator
	shadow_color = theme.shadow
}
