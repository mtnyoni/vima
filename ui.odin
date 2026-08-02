package main

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"


WINDOW_WIDTH: i32 = 720
WINDOW_HEIGHT: i32 = 400
WINDOW_RADIUS: i32 = 8
WINDOW_BORDER_WIDTH: i32 = 1
INPUT_HEIGHT: f32 = 36
INPUT_RADIUS: i32 = 6
INPUT_FONT_SIZE: f32 = 18

CARET_HEIGHT_RATIO: f32 = 0.75
CARET_BLINK_INTERVAL: u64 = 500
CARET_TYPING_HOLD: u64 = 650


Color :: struct {
	r: u8,
	g: u8,
	b: u8,
	a: u8,
}

app_color: Color = Color{48, 52, 70, 255} // Frappé Base: #303446
input_border_color: Color = Color{81, 87, 109, 255} // Frappé Surface 1: #51576d
window_border_color: Color = Color{98, 104, 128, 255} // Frappé Surface 2: #626880
text_color: Color = Color{198, 208, 245, 255} // Frappé Text: #c6d0f5

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

rounded_window_shape :: proc(width, height, radius: i32) -> ^sdl.Surface {
	shape := sdl.CreateSurface(width, height, .RGBA8888)
	if shape == nil {
		return nil
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			corner := false
			center_x, center_y: i32

			switch {
			case x < radius && y < radius:
				corner = true
				center_x, center_y = radius, radius

			case x >= width - radius && y < radius:
				corner = true
				center_x, center_y = width - radius - 1, radius

			case x < radius && y >= height - radius:
				corner = true
				center_x, center_y = radius, height - radius - 1

			case x >= width - radius && y >= height - radius:
				corner = true
				center_x, center_y = width - radius - 1, height - radius - 1
			}

			alpha: u8 = 255
			if corner {
				dx := x - center_x
				dy := y - center_y
				if dx * dx + dy * dy > radius * radius {
					alpha = 0
				}
			}

			if !sdl.WriteSurfacePixel(shape, x, y, 255, 255, 255, alpha) {
				sdl.DestroySurface(shape)
				return nil
			}
		}
	}

	return shape
}


main_window :: proc(title: cstring) {
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

	window := sdl.CreateWindow(
		title,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		{.HIGH_PIXEL_DENSITY, .BORDERLESS, .TRANSPARENT},
	)
	assert(window != nil)
	defer sdl.DestroyWindow(window)

	shape := rounded_window_shape(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_RADIUS)
	assert(shape != nil)
	assert(sdl.SetWindowShape(window, shape))
	sdl.DestroySurface(shape)

	renderer := sdl.CreateRenderer(window, nil)
	assert(renderer != nil)
	defer sdl.DestroyRenderer(renderer)

	render_width, render_height: i32
	assert(sdl.GetCurrentRenderOutputSize(renderer, &render_width, &render_height))
	render_scale_x := f32(render_width) / f32(WINDOW_WIDTH)
	render_scale_y := f32(render_height) / f32(WINDOW_HEIGHT)

	font := ttf.OpenFont(
		"/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
		INPUT_FONT_SIZE * render_scale_y,
	)
	assert(font != nil)
	defer ttf.CloseFont(font)
	font_height := ttf.GetFontHeight(font)

	text_engine := ttf.CreateRendererTextEngine(renderer)
	assert(text_engine != nil)
	defer ttf.DestroyRendererTextEngine(text_engine)

	input_text := ttf.CreateText(text_engine, font, "", 0)
	assert(input_text != nil)
	defer ttf.DestroyText(input_text)
	assert(ttf.SetTextColor(input_text, text_color.r, text_color.g, text_color.b, text_color.a))

	border_surface := rounded_window_border(
		render_width,
		render_height,
		i32(f32(WINDOW_RADIUS) * render_scale_y),
		i32(f32(WINDOW_BORDER_WIDTH) * render_scale_y),
		window_border_color,
	)
	assert(border_surface != nil)
	border_texture := sdl.CreateTextureFromSurface(renderer, border_surface)
	sdl.DestroySurface(border_surface)
	assert(border_texture != nil)
	defer sdl.DestroyTexture(border_texture)

	input_x := 4 * render_scale_x
	input_y := 4 * render_scale_y
	input_width := f32(render_width) - input_x * 2
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

	input: strings.Builder
	strings.builder_init(&input, 0, 256)
	defer strings.builder_destroy(&input)

	assert(sdl.StartTextInput(window))
	defer _ = sdl.StopTextInput(window)

	input_dirty := true
	caret_state: Caret_State
	running := true
	for running {
		e: sdl.Event

		for sdl.PollEvent(&e) {
			#partial switch e.type {
			case .KEY_DOWN:
				if e.key.scancode == .ESCAPE {
					running = false
				} else if e.key.scancode == .BACKSPACE {
					_, _ = strings.pop_rune(&input)
					input_dirty = true
					caret_state.last_input_at = sdl.GetTicks()
					caret_state.has_input_activity = true
				}

			case .TEXT_INPUT:
				strings.write_string(&input, string(e.text.text))
				input_dirty = true
				caret_state.last_input_at = sdl.GetTicks()
				caret_state.has_input_activity = true

			case .QUIT:
				running = false
			}
		}

		sdl.SetRenderDrawColor(renderer, app_color.r, app_color.g, app_color.b, app_color.a)
		sdl.RenderClear(renderer)

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

		sdl.RenderTexture(renderer, border_texture, nil, nil)
		sdl.RenderPresent(renderer)
	}
}
