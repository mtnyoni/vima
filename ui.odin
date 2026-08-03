package main

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

when ODIN_OS == .Windows {
	DEFAULT_FONT_PATH :: "C:/Windows/Fonts/segoeui.ttf"
} else {
	DEFAULT_FONT_PATH :: "/usr/share/fonts/google-noto/NotoSans-Regular.ttf"
}

WINDOW_WIDTH: i32 = 720
WINDOW_HEIGHT: i32 = 400
WINDOW_RADIUS: i32 = 8
WINDOW_BORDER_WIDTH: i32 = 1
WINDOW_SHADOW_PADDING: i32 = 12
INPUT_HEIGHT: f32 = 36
INPUT_RADIUS: i32 = 6
INPUT_FONT_SIZE: f32 = 18
FONT_SIZE_SCALE: f32 = 1.2
LIST_HIGHLIGHT_RADIUS: i32 = 5
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

Caret_State :: struct {
	last_input_at:      u64,
	has_input_activity: bool,
}

render_caret :: proc(
	renderer: ^sdl.Renderer,
	state: ^Caret_State,
	x, input_y, input_height, width, font_height: f32,
) {
	now := sdl.GetTicks()
	visible := false

	if state.has_input_activity {
		idle_time := now - state.last_input_at
		if idle_time <= CARET_TYPING_HOLD {
			visible = true
		} else {
			blink_time := idle_time - CARET_TYPING_HOLD
			visible = blink_time / CARET_BLINK_INTERVAL % 2 == 0
		}
	} else {
		visible = now / CARET_BLINK_INTERVAL % 2 == 0
	}

	if !visible {
		return
	}

	caret_height := font_height * CARET_HEIGHT_RATIO
	caret := sdl.FRect {
		x = x,
		y = input_y + (input_height - caret_height) / 2,
		w = width,
		h = caret_height,
	}
	sdl.SetRenderDrawColor(renderer, text_color.r, text_color.g, text_color.b, text_color.a)
	sdl.RenderFillRect(renderer, &caret)
}

create_text :: proc(
	engine: ^ttf.TextEngine,
	font: ^ttf.Font,
	value: cstring,
	color: Color,
) -> ^ttf.Text {
	text := ttf.CreateText(engine, font, value, c.size_t(len(string(value))))
	if text == nil {
		return nil
	}
	if !ttf.SetTextColor(text, color.r, color.g, color.b, color.a) {
		ttf.DestroyText(text)
		return nil
	}
	return text
}

inside_rounded_rect :: proc(x, y, width, height, radius: i32) -> bool {
	if x < 0 || y < 0 || x >= width || y >= height {
		return false
	}

	center_x := radius if x < radius else width - radius - 1
	center_y := radius if y < radius else height - radius - 1
	if x >= radius && x < width - radius || y >= radius && y < height - radius {
		return true
	}

	dx := x - center_x
	dy := y - center_y
	return dx * dx + dy * dy <= radius * radius
}

rounded_window_border :: proc(
	width, height, radius, border_width: i32,
	color: Color,
) -> ^sdl.Surface {
	border := sdl.CreateSurface(width, height, .RGBA8888)
	if border == nil {
		return nil
	}

	inner_radius := radius - border_width
	if inner_radius < 0 {
		inner_radius = 0
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			outer := inside_rounded_rect(x, y, width, height, radius)
			inner := inside_rounded_rect(
				x - border_width,
				y - border_width,
				width - border_width * 2,
				height - border_width * 2,
				inner_radius,
			)

			alpha: u8 = 0
			if outer && !inner {
				alpha = 255
			}

			if !sdl.WriteSurfacePixel(border, x, y, color.r, color.g, color.b, alpha) {
				sdl.DestroySurface(border)
				return nil
			}
		}
	}

	return border
}

rounded_input_surface :: proc(
	width, height, radius, border_width: i32,
	background: Color,
	border_color: Color,
) -> ^sdl.Surface {
	surface := sdl.CreateSurface(width, height, .RGBA8888)
	if surface == nil {
		return nil
	}

	inner_radius := radius - border_width
	if inner_radius < 0 {
		inner_radius = 0
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			outer := inside_rounded_rect(x, y, width, height, radius)
			inner := inside_rounded_rect(
				x - border_width,
				y - border_width,
				width - border_width * 2,
				height - border_width * 2,
				inner_radius,
			)

			r, g, b, a: u8
			switch {
			case !outer:
				r, g, b, a = 0, 0, 0, 0

			case !inner:
				r, g, b, a = border_color.r, border_color.g, border_color.b, border_color.a

			case:
				r, g, b, a = background.r, background.g, background.b, background.a
			}

			if !sdl.WriteSurfacePixel(surface, x, y, r, g, b, a) {
				sdl.DestroySurface(surface)
				return nil
			}
		}
	}

	return surface
}

window_backdrop_surface :: proc(
	content_width, content_height, padding, radius: i32,
	background, shadow: Color,
) -> ^sdl.Surface {
	width := content_width + padding * 2
	height := content_height + padding * 2
	surface := sdl.CreateSurface(width, height, .RGBA8888)
	if surface == nil {
		return nil
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			r, g, b, a: u8
			if inside_rounded_rect(
				x - padding,
				y - padding,
				content_width,
				content_height,
				radius,
			) {
				r, g, b, a = background.r, background.g, background.b, background.a
			} else {
				r, g, b, a = shadow.r, shadow.g, shadow.b, 0
				for distance in 1 ..< padding + 1 {
					if inside_rounded_rect(
						x - (padding - distance),
						y - (padding - distance),
						content_width + distance * 2,
						content_height + distance * 2,
						radius + distance,
					) {
						a = u8((padding - distance + 1) * i32(shadow.a) / padding)
						break
					}
				}
			}

			if !sdl.WriteSurfacePixel(surface, x, y, r, g, b, a) {
				sdl.DestroySurface(surface)
				return nil
			}
		}
	}

	return surface
}


main_window :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)

	defer {
		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}

		mem.tracking_allocator_destroy(&track)
	}

	context.allocator = mem.tracking_allocator(&track)

	assert(sdl.Init(sdl.INIT_VIDEO))
	defer sdl.Quit()

	assert(ttf.Init())
	defer ttf.Quit()

	window_width := WINDOW_WIDTH + WINDOW_SHADOW_PADDING * 2
	window_height := WINDOW_HEIGHT + WINDOW_SHADOW_PADDING * 2
	window := sdl.CreateWindow(
		"Vima",
		window_width,
		window_height,
		{.HIGH_PIXEL_DENSITY, .BORDERLESS, .TRANSPARENT},
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	shape := window_backdrop_surface(
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		WINDOW_SHADOW_PADDING,
		WINDOW_RADIUS,
		app_color,
		shadow_color,
	)
	assert(shape != nil)
	assert(sdl.SetWindowShape(window, shape))
	sdl.DestroySurface(shape)

	renderer := sdl.CreateRenderer(window, nil)
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	render_width, render_height: i32
	assert(sdl.GetCurrentRenderOutputSize(renderer, &render_width, &render_height))
	render_scale_x := f32(render_width) / f32(window_width)
	render_scale_y := f32(render_height) / f32(window_height)
	shadow_padding_x := f32(WINDOW_SHADOW_PADDING) * render_scale_x
	shadow_padding_y := f32(WINDOW_SHADOW_PADDING) * render_scale_y
	content_width := render_width - i32(shadow_padding_x) * 2
	content_height := render_height - i32(shadow_padding_y) * 2
	content_rect := sdl.FRect {
		x = shadow_padding_x,
		y = shadow_padding_y,
		w = f32(content_width),
		h = f32(content_height),
	}

	backdrop_surface := window_backdrop_surface(
		content_width,
		content_height,
		i32(shadow_padding_x),
		i32(f32(WINDOW_RADIUS) * render_scale_y),
		app_color,
		shadow_color,
	)
	assert(backdrop_surface != nil)
	backdrop_texture := sdl.CreateTextureFromSurface(renderer, backdrop_surface)
	sdl.DestroySurface(backdrop_surface)
	assert(backdrop_texture != nil)
	defer sdl.DestroyTexture(backdrop_texture)

	font := ttf.OpenFont(DEFAULT_FONT_PATH, INPUT_FONT_SIZE * FONT_SIZE_SCALE * render_scale_y)
	assert(font != nil)
	defer ttf.CloseFont(font)
	font_height := ttf.GetFontHeight(font)
	list_font_size := system_font_size() * FONT_SIZE_SCALE
	list_name_font := ttf.OpenFont(DEFAULT_FONT_PATH, list_font_size * render_scale_y)
	assert(list_name_font != nil)
	defer ttf.CloseFont(list_name_font)
	list_name_height := ttf.GetFontHeight(list_name_font)
	list_description_font := ttf.OpenFont(
		DEFAULT_FONT_PATH,
		list_font_size * LIST_DESCRIPTION_SIZE_RATIO * render_scale_y,
	)
	assert(list_description_font != nil)
	defer ttf.CloseFont(list_description_font)
	list_description_height := ttf.GetFontHeight(list_description_font)

	text_engine := ttf.CreateRendererTextEngine(renderer)
	assert(text_engine != nil)
	defer ttf.DestroyRendererTextEngine(text_engine)

	input_text := ttf.CreateText(text_engine, font, "", 0)
	assert(input_text != nil)
	defer ttf.DestroyText(input_text)
	assert(ttf.SetTextColor(input_text, text_color.r, text_color.g, text_color.b, text_color.a))

	application_name_texts: [len(DUMMY_APPLICATIONS)]^ttf.Text
	application_description_texts: [len(DUMMY_APPLICATIONS)]^ttf.Text
	for application, index in DUMMY_APPLICATIONS {
		application_name_texts[index] = create_text(
			text_engine,
			list_name_font,
			application.name,
			text_color,
		)
		assert(application_name_texts[index] != nil)
		application_description_texts[index] = create_text(
			text_engine,
			list_description_font,
			application.description,
			subtext_color,
		)
		assert(application_description_texts[index] != nil)
	}

	defer {
		for text in application_name_texts {
			ttf.DestroyText(text)
		}

		for text in application_description_texts {
			ttf.DestroyText(text)
		}
	}

	border_surface := rounded_window_border(
		content_width,
		content_height,
		i32(f32(WINDOW_RADIUS) * render_scale_y),
		i32(f32(WINDOW_BORDER_WIDTH) * render_scale_y),
		window_border_color,
	)
	assert(border_surface != nil)
	border_texture := sdl.CreateTextureFromSurface(renderer, border_surface)
	sdl.DestroySurface(border_surface)
	assert(border_texture != nil)
	defer sdl.DestroyTexture(border_texture)

	input_x := shadow_padding_x + 4 * render_scale_x
	input_y := shadow_padding_y + 4 * render_scale_y
	input_width := f32(content_width) - 8 * render_scale_x
	input_height := INPUT_HEIGHT * render_scale_y
	input_surface := rounded_input_surface(
		i32(input_width),
		i32(input_height),
		i32(f32(INPUT_RADIUS) * render_scale_y),
		i32(f32(WINDOW_BORDER_WIDTH) * render_scale_y),
		app_color,
		input_border_color,
	)
	assert(input_surface != nil)
	input_texture := sdl.CreateTextureFromSurface(renderer, input_surface)
	sdl.DestroySurface(input_surface)
	assert(input_texture != nil)
	defer sdl.DestroyTexture(input_texture)

	input_rect := sdl.FRect {
		x = input_x,
		y = input_y,
		w = input_width,
		h = input_height,
	}
	list_x := input_x
	list_y := input_y + input_height + 4 * render_scale_y
	list_width := input_width
	list_height := shadow_padding_y + f32(content_height) - 4 * render_scale_y - list_y
	row_height := list_font_size * LIST_ROW_HEIGHT_RATIO * render_scale_y
	visible_row_count := max(1, int(list_height / row_height))
	row_height = list_height / f32(visible_row_count)
	max_scroll_offset := max(0, len(DUMMY_APPLICATIONS) - visible_row_count)
	list_clip := sdl.Rect {
		x = i32(list_x),
		y = i32(list_y),
		w = i32(list_width),
		h = i32(list_height),
	}
	highlight_surface := rounded_input_surface(
		i32(list_width),
		i32(row_height),
		i32(f32(LIST_HIGHLIGHT_RADIUS) * render_scale_y),
		0,
		selected_color,
		selected_color,
	)
	assert(highlight_surface != nil)
	highlight_texture := sdl.CreateTextureFromSurface(renderer, highlight_surface)
	sdl.DestroySurface(highlight_surface)
	assert(highlight_texture != nil)
	defer sdl.DestroyTexture(highlight_texture)

	input: strings.Builder
	strings.builder_init(&input, 0, 256)
	defer strings.builder_destroy(&input)

	assert(sdl.StartTextInput(window))
	defer _ = sdl.StopTextInput(window)

	input_dirty := true
	caret_state: Caret_State
	selected_index := 0
	scroll_offset := 0
	last_wheel_scroll_at: u64
	running := true
	for running {
		e: sdl.Event

		for sdl.PollEvent(&e) {
			#partial switch e.type {
			case .KEY_DOWN:
				#partial switch e.key.scancode {
				case .ESCAPE:
					running = false
					break

				case .UP:
					selected_index = max(0, selected_index - 1)
					break

				case .DOWN:
					selected_index = min(len(DUMMY_APPLICATIONS) - 1, selected_index + 1)
					break

				case .PAGEUP:
					selected_index = max(0, selected_index - visible_row_count)
					break

				case .PAGEDOWN:
					selected_index = min(
						len(DUMMY_APPLICATIONS) - 1,
						selected_index + visible_row_count,
					)
					break

				case .BACKSPACE:
					_, _ = strings.pop_rune(&input)
					input_dirty = true
					caret_state.last_input_at = sdl.GetTicks()
					caret_state.has_input_activity = true
					break
				}


			case .TEXT_INPUT:
				strings.write_string(&input, string(e.text.text))
				input_dirty = true
				caret_state.last_input_at = sdl.GetTicks()
				caret_state.has_input_activity = true

			case .MOUSE_WHEEL:
				now := sdl.GetTicks()
				if e.wheel.y != 0 &&
				   (last_wheel_scroll_at == 0 ||
						   now - last_wheel_scroll_at >= WHEEL_SCROLL_INTERVAL) {
					direction := -1 if e.wheel.y > 0 else 1
					selected_index = clamp(
						selected_index + direction,
						0,
						len(DUMMY_APPLICATIONS) - 1,
					)
					last_wheel_scroll_at = now
				}

			case .MOUSE_BUTTON_DOWN:
				if e.button.button == sdl.BUTTON_LEFT {
					mouse_x := e.button.x * render_scale_x
					mouse_y := e.button.y * render_scale_y
					if mouse_x >= list_x &&
					   mouse_x < list_x + list_width &&
					   mouse_y >= list_y &&
					   mouse_y < list_y + list_height {
						visible_index := int((mouse_y - list_y) / row_height)
						clicked_index := scroll_offset + visible_index
						if clicked_index < len(DUMMY_APPLICATIONS) &&
						   visible_index < visible_row_count {
							selected_index = clicked_index
						}
					}
				}

			case .QUIT:
				running = false
			}
		}

		if selected_index < scroll_offset {
			scroll_offset = selected_index
		} else if selected_index >= scroll_offset + visible_row_count {
			scroll_offset = selected_index - visible_row_count + 1
		}
		scroll_offset = min(scroll_offset, max_scroll_offset)

		sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0)
		sdl.RenderClear(renderer)
		sdl.RenderTexture(renderer, backdrop_texture, nil, nil)

		sdl.RenderTexture(renderer, input_texture, nil, &input_rect)

		if input_dirty {
			input_value, input_error := strings.to_cstring(&input)
			assert(input_error == nil)
			assert(ttf.SetTextString(input_text, input_value, c.size_t(len(input.buf))))
			input_dirty = false
		}

		text_width: i32
		assert(ttf.GetTextSize(input_text, &text_width, nil))
		text_x := input_x + 6 * render_scale_x
		text_y := input_y + (input_height - f32(font_height)) / 2
		assert(ttf.DrawRendererText(input_text, text_x, text_y))

		render_caret(
			renderer,
			&caret_state,
			text_x + f32(text_width) + render_scale_x,
			input_y,
			input_height,
			render_scale_x,
			f32(font_height),
		)

		assert(sdl.SetRenderClipRect(renderer, &list_clip))
		visible_end := min(len(DUMMY_APPLICATIONS), scroll_offset + visible_row_count)
		for application_index in scroll_offset ..< visible_end {
			visible_index := application_index - scroll_offset
			row_y := list_y + f32(visible_index) * row_height

			if application_index == selected_index {
				selected_rect := sdl.FRect {
					x = list_x,
					y = row_y,
					w = list_width,
					h = row_height,
				}
				sdl.RenderTexture(renderer, highlight_texture, nil, &selected_rect)
			}

			row_text_x := list_x + 10 * render_scale_x
			name_width: i32
			assert(ttf.GetTextSize(application_name_texts[application_index], &name_width, nil))
			assert(
				ttf.DrawRendererText(
					application_name_texts[application_index],
					row_text_x,
					row_y + (row_height - f32(list_name_height)) / 2,
				),
			)
			assert(
				ttf.DrawRendererText(
					application_description_texts[application_index],
					row_text_x + f32(name_width) + 8 * render_scale_x,
					row_y + (row_height - f32(list_description_height)) / 2,
				),
			)

			separator := sdl.FRect {
				x = list_x + 10 * render_scale_x,
				y = row_y + row_height - render_scale_y,
				w = list_width - 20 * render_scale_x,
				h = render_scale_y,
			}

			sdl.SetRenderDrawColor(
				renderer,
				separator_color.r,
				separator_color.g,
				separator_color.b,
				separator_color.a,
			)
			sdl.RenderFillRect(renderer, &separator)
		}
		assert(sdl.SetRenderClipRect(renderer, nil))

		sdl.RenderTexture(renderer, border_texture, nil, &content_rect)
		sdl.RenderPresent(renderer)
	}
}
