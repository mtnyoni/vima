package main

import "core:fmt"
import "core:mem"
import "core:strings"

import sdl "vendor:sdl3"

WINDOW_WIDTH: i32 = 720
WINDOW_HEIGHT: i32 = 400
WINDOW_RADIUS: i32 = 8
WINDOW_BORDER_WIDTH: i32 = 1
INPUT_HEIGHT: f32 = 48

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

	border_surface := rounded_window_border(
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
		WINDOW_RADIUS,
		WINDOW_BORDER_WIDTH,
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
	defer sdl.StopTextInput(window)

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
				}

			case .TEXT_INPUT:
				strings.write_string(&input, string(e.text))

			case .QUIT:
				running = false
			}
		}

		sdl.SetRenderDrawColor(renderer, 30, 30, 30, 255)
		sdl.RenderClear(renderer)

		input_rect := sdl.FRect{
			x = 0,
			y = 0,
			w = f32(WINDOW_WIDTH),
			h = INPUT_HEIGHT,
		}
		sdl.SetRenderDrawColor(renderer, 42, 42, 42, 255)
		sdl.RenderFillRect(renderer, &input_rect)

		input_divider := sdl.FRect{
			x = 0,
			y = INPUT_HEIGHT-1,
			w = f32(WINDOW_WIDTH),
			h = 1,
		}
		sdl.SetRenderDrawColor(renderer, 80, 80, 80, 255)
		sdl.RenderFillRect(renderer, &input_divider)

		input_text := strings.to_cstring(&input) or_return
		sdl.SetRenderDrawColor(renderer, 235, 235, 235, 255)
		sdl.RenderDebugText(renderer, 12, 20, input_text)
		sdl.RenderDebugText(renderer, 12+f32(len(input.buf))*8, 20, "|")

		sdl.RenderTexture(renderer, border_texture, nil, nil)
		sdl.RenderPresent(renderer)
	}
}
