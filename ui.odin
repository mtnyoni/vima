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

rounded_window_border :: proc(width, height, radius, border_width: i32) -> ^sdl.Surface {
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

			if !sdl.WriteSurfacePixel(border, x, y, 100, 100, 100, alpha) {
				sdl.DestroySurface(border)
				return nil
			}
		}
	}

	return border
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
	render_scale_x := f32(render_width)/f32(WINDOW_WIDTH)
	render_scale_y := f32(render_height)/f32(WINDOW_HEIGHT)

	font := ttf.OpenFont(
		"/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
		20*render_scale_y,
	)
	assert(font != nil)
	defer ttf.CloseFont(font)

	text_engine := ttf.CreateRendererTextEngine(renderer)
	assert(text_engine != nil)
	defer ttf.DestroyRendererTextEngine(text_engine)

	input_text := ttf.CreateText(text_engine, font, "", 0)
	assert(input_text != nil)
	defer ttf.DestroyText(input_text)
	assert(ttf.SetTextColor(input_text, 235, 235, 235, 255))

	border_surface := rounded_window_border(
		render_width,
		render_height,
		i32(f32(WINDOW_RADIUS)*render_scale_y),
		i32(f32(WINDOW_BORDER_WIDTH)*render_scale_y),
	)
	assert(border_surface != nil)
	border_texture := sdl.CreateTextureFromSurface(renderer, border_surface)
	sdl.DestroySurface(border_surface)
	assert(border_texture != nil)
	defer sdl.DestroyTexture(border_texture)

	input: strings.Builder
	strings.builder_init(&input, 0, 256)
	defer strings.builder_destroy(&input)

	assert(sdl.StartTextInput(window))
	defer _ = sdl.StopTextInput(window)

	input_dirty := true
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
				}

			case .TEXT_INPUT:
				strings.write_string(&input, string(e.text.text))
				input_dirty = true

			case .QUIT:
				running = false
			}
		}

		sdl.SetRenderDrawColor(renderer, 30, 30, 30, 255)
		sdl.RenderClear(renderer)

		InputRectMargin :: struct {
			x: f32,
			y: f32,
		}

		margs := InputRectMargin {
			x = 4*render_scale_x,
			y = 4*render_scale_y,
		}
		input_height := INPUT_HEIGHT*render_scale_y

		input_rect := sdl.FRect {
			x = margs.x,
			y = margs.y,
			w = f32(render_width)-margs.x*2,
			h = input_height,
		}
		sdl.SetRenderDrawColor(renderer, 42, 42, 42, 255)
		sdl.RenderFillRect(renderer, &input_rect)

		input_divider := sdl.FRect {
			x = margs.x,
			y = margs.y+input_height-render_scale_y,
			w = f32(render_width)-margs.x*2,
			h = render_scale_y,
		}
		sdl.SetRenderDrawColor(renderer, 80, 80, 80, 255)
		sdl.RenderFillRect(renderer, &input_divider)

		if input_dirty {
			input_value, input_error := strings.to_cstring(&input)
			assert(input_error == nil)
			assert(ttf.SetTextString(input_text, input_value, c.size_t(len(input.buf))))
			input_dirty = false
		}

		text_x := margs.x+6*render_scale_x
		text_y := margs.y+10*render_scale_y
		assert(ttf.DrawRendererText(input_text, text_x, text_y))

		text_width, text_height: i32
		assert(ttf.GetTextSize(input_text, &text_width, &text_height))
		caret := sdl.FRect {
			x = text_x+f32(text_width)+render_scale_x,
			y = text_y,
			w = render_scale_x,
			h = f32(text_height),
		}
		sdl.SetRenderDrawColor(renderer, 235, 235, 235, 255)
		sdl.RenderFillRect(renderer, &caret)

		sdl.RenderTexture(renderer, border_texture, nil, nil)
		sdl.RenderPresent(renderer)
	}
}
