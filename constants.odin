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
WHEEL_SCROLL_INTERVAL: u64 = 90

CARET_HEIGHT_RATIO: f32 = 0.75
CARET_BLINK_INTERVAL: u64 = 500
CARET_TYPING_HOLD: u64 = 650


Color :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

app_color: Color = Color{35, 38, 52, 255} // Frappé Crust: #232634
input_border_color: Color = Color{81, 87, 109, 255} // Frappé Surface 1: #51576d
window_border_color: Color = Color{98, 104, 128, 255} // Frappé Surface 2: #626880
text_color: Color = Color{198, 208, 245, 255} // Frappé Text: #c6d0f5
subtext_color: Color = Color{165, 173, 206, 255} // Frappé Subtext 0: #a5adce
selected_color: Color = Color{65, 69, 89, 255} // Frappé Surface 0: #414559
separator_color: Color = Color{41, 44, 60, 255} // Frappé Mantle: #292c3c
shadow_color: Color = Color{35, 38, 52, 90} // Frappé Crust with soft alpha
