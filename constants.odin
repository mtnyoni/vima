package main

when ODIN_OS == .Windows {
	DEFAULT_FONT_PATH :: "C:/Windows/Fonts/segoeui.ttf"
} else {
	DEFAULT_FONT_PATH :: "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"
}

WINDOW_WIDTH: i32 = 720
WINDOW_HEIGHT: i32 = 400
WINDOW_RADIUS: i32 = 8
WINDOW_BORDER_WIDTH: i32 = 1
WINDOW_SHADOW_PADDING: i32 = 6
INPUT_HEIGHT: f32 = 36
INPUT_RADIUS: i32 = 6
INPUT_FONT_SIZE: f32 = 11
FONT_SIZE_SCALE: f32 = 1.2
LIST_HIGHLIGHT_RADIUS: i32 = 5
LIST_ICON_SIZE: f32 = 18
LIST_DESCRIPTION_SIZE_RATIO :: 11.0 / 13.0
LIST_ROW_HEIGHT_RATIO :: 32.0 / 13.0
WHEEL_SCROLL_INTERVAL: u64 = 30

CARET_HEIGHT_RATIO: f32 = 0.75
CARET_BLINK_INTERVAL: u64 = 500
CARET_TYPING_HOLD: u64 = 650


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
	selected:      Color,
	separator:     Color,
	shadow:        Color,
}

// Catppuccin Frappé
DARK_UI_THEME :: UI_Theme {
	app           = {35, 38, 52, 255},
	input_border  = {81, 87, 109, 255},
	window_border = {98, 104, 128, 255},
	text          = {198, 208, 245, 255},
	subtext       = {165, 173, 206, 255},
	selected      = {65, 69, 89, 255},
	separator     = {41, 44, 60, 255},
	shadow        = {35, 38, 52, 90},
}

// Catppuccin Latte
LIGHT_UI_THEME :: UI_Theme {
	app           = {220, 224, 232, 255},
	input_border  = {188, 192, 204, 255},
	window_border = {172, 176, 190, 255},
	text          = {76, 79, 105, 255},
	subtext       = {108, 111, 133, 255},
	selected      = {204, 208, 218, 255},
	separator     = {230, 233, 239, 255},
	shadow        = {76, 79, 105, 55},
}

app_color: Color = DARK_UI_THEME.app
input_border_color: Color = DARK_UI_THEME.input_border
window_border_color: Color = DARK_UI_THEME.window_border
text_color: Color = DARK_UI_THEME.text
subtext_color: Color = DARK_UI_THEME.subtext
selected_color: Color = DARK_UI_THEME.selected
separator_color: Color = DARK_UI_THEME.separator
shadow_color: Color = DARK_UI_THEME.shadow

apply_ui_theme :: proc(theme: UI_Theme) {
	app_color = theme.app
	input_border_color = theme.input_border
	window_border_color = theme.window_border
	text_color = theme.text
	subtext_color = theme.subtext
	selected_color = theme.selected
	separator_color = theme.separator
	shadow_color = theme.shadow
}
