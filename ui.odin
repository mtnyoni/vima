package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

import sdl "vendor:sdl3"
import image "vendor:sdl3/image"
import ttf "vendor:sdl3/ttf"


Caret_State :: struct {
	last_input_at:      u64,
	has_input_activity: bool,
}

main_window :: proc(toggle_server: ^Toggle_Server) {
	when ODIN_OS == .Linux {
		// Prefer the native layer-shell backend when the compositor advertises
		// it. SDL_VIDEO_DRIVER remains available as an explicit override.
		if sdl.GetHint(sdl.HINT_VIDEO_DRIVER) == nil {
			driver_order: cstring = "x11,wayland"
			if vima_layer_shell_supported() != 0 {
				driver_order = "wayland,x11"
			}

			_ = sdl.SetHintWithPriority(sdl.HINT_VIDEO_DRIVER, driver_order, .DEFAULT)
		}
	}

	assert(sdl.Init(sdl.INIT_VIDEO))
	defer sdl.Quit()
	apply_system_theme()

	assert(ttf.Init())
	defer ttf.Quit()

	requested_display_scale: f32
	rebuild_ui := true
	for rebuild_ui {
		rebuild_ui = false

		base_window_width := WINDOW_WIDTH + WINDOW_SHADOW_PADDING * 2
		base_window_height := WINDOW_HEIGHT + WINDOW_SHADOW_PADDING * 2
		display_scale := requested_display_scale
		if display_scale <= 0 {
			display_scale = sdl.GetDisplayContentScale(sdl.GetPrimaryDisplay())
		}

		if display_scale <= 0 {
			display_scale = 1
		}

		window_coordinate_scale: f32 = 1
		when ODIN_OS == .Linux {
			if string(sdl.GetCurrentVideoDriver()) == "x11" {
				// X11 uses physical window coordinates. Enlarge the window so its
				// content has the same physical size as the native Wayland version.
				window_coordinate_scale = display_scale
			}
		}

		window_width := i32(math.round(f32(base_window_width) * window_coordinate_scale))
		window_height := i32(math.round(f32(base_window_height) * window_coordinate_scale))
		layer_shell_mode := false
		when ODIN_OS == .Linux {
			layer_shell_mode = string(sdl.GetCurrentVideoDriver()) == "wayland"
		}

		window: ^sdl.Window
		if layer_shell_mode {
			properties := sdl.CreateProperties()
			assert(properties != 0)
			assert(sdl.SetStringProperty(properties, sdl.PROP_WINDOW_CREATE_TITLE_STRING, "Vima"))
			assert(
				sdl.SetNumberProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_WIDTH_NUMBER,
					i64(window_width),
				),
			)

			assert(
				sdl.SetNumberProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_HEIGHT_NUMBER,
					i64(window_height),
				),
			)

			assert(sdl.SetBooleanProperty(properties, sdl.PROP_WINDOW_CREATE_HIDDEN_BOOLEAN, true))
			assert(
				sdl.SetBooleanProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN,
					true,
				),
			)

			assert(
				sdl.SetBooleanProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_TRANSPARENT_BOOLEAN,
					true,
				),
			)
			assert(
				sdl.SetBooleanProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_WAYLAND_SURFACE_ROLE_CUSTOM_BOOLEAN,
					true,
				),
			)

			assert(
				sdl.SetBooleanProperty(
					properties,
					sdl.PROP_WINDOW_CREATE_WAYLAND_CREATE_EGL_WINDOW_BOOLEAN,
					true,
				),
			)

			window = sdl.CreateWindowWithProperties(properties)
			sdl.DestroyProperties(properties)
		} else {
			window = sdl.CreateWindow(
				"Vima",
				window_width,
				window_height,
				{
					.HIDDEN,
					.UTILITY,
					.HIGH_PIXEL_DENSITY,
					.BORDERLESS,
					.TRANSPARENT,
					.ALWAYS_ON_TOP,
				},
			)
		}
		assert(window != nil)
		defer sdl.DestroyWindow(window)
		window_id := sdl.GetWindowID(window)

		layer_shell_state: rawptr
		when ODIN_OS == .Linux {
			if layer_shell_mode {
				window_properties := sdl.GetWindowProperties(window)
				display := sdl.GetPointerProperty(
					window_properties,
					sdl.PROP_WINDOW_WAYLAND_DISPLAY_POINTER,
					nil,
				)

				surface := sdl.GetPointerProperty(
					window_properties,
					sdl.PROP_WINDOW_WAYLAND_SURFACE_POINTER,
					nil,
				)

				layer_shell_state = vima_layer_shell_attach(display, surface)
				if layer_shell_state == nil {
					fmt.eprintln("Unable to create the Wayland layer-shell surface")
					return
				}

				window_width = i32(vima_layer_shell_width(layer_shell_state))
				window_height = i32(vima_layer_shell_height(layer_shell_state))
				assert(sdl.SetWindowSize(window, window_width, window_height))
			}
		}
		defer {
			when ODIN_OS == .Linux {
				if layer_shell_state != nil {
					vima_layer_shell_destroy(layer_shell_state)
				}
			}
		}

		if !layer_shell_mode {
			shape := window_backdrop_surface(
				i32(math.round(f32(WINDOW_WIDTH) * window_coordinate_scale)),
				i32(math.round(f32(WINDOW_HEIGHT) * window_coordinate_scale)),
				i32(math.round(f32(WINDOW_SHADOW_PADDING) * window_coordinate_scale)),
				i32(math.round(f32(WINDOW_RADIUS) * window_coordinate_scale)),
				app_color,
				shadow_color,
			)
			assert(shape != nil)
			assert(sdl.SetWindowShape(window, shape))
			sdl.DestroySurface(shape)
		}

		renderer := sdl.CreateRenderer(window, nil)
		assert(renderer != nil)
		defer sdl.DestroyRenderer(renderer)

		render_width, render_height: i32
		assert(sdl.GetCurrentRenderOutputSize(renderer, &render_width, &render_height))
		pixel_scale_x := f32(render_width) / f32(window_width)
		pixel_scale_y := f32(render_height) / f32(window_height)
		// A Wayland layer surface covers the output. The launcher panel remains
		// at its normal scaled size and is centered inside that transparent area.
		panel_width := render_width
		panel_height := render_height
		if layer_shell_mode {
			panel_width = i32(math.round(f32(base_window_width) * pixel_scale_x))
			panel_height = i32(math.round(f32(base_window_height) * pixel_scale_y))
			panel_width = min(panel_width, render_width)
			panel_height = min(panel_height, render_height)
		}

		panel_x := f32(render_width - panel_width) / 2
		panel_y := f32(render_height - panel_height) / 2
		panel_rect := sdl.FRect {
			x = panel_x,
			y = panel_y,
			w = f32(panel_width),
			h = f32(panel_height),
		}

		// UI scale controls physical content size. Pixel scale only converts
		// window/input coordinates into renderer coordinates.
		render_scale_x := f32(panel_width) / f32(base_window_width)
		render_scale_y := f32(panel_height) / f32(base_window_height)
		initial_display_scale := sdl.GetWindowDisplayScale(window)
		initial_pixel_density := sdl.GetWindowPixelDensity(window)
		shadow_padding_x := f32(WINDOW_SHADOW_PADDING) * render_scale_x
		shadow_padding_y := f32(WINDOW_SHADOW_PADDING) * render_scale_y
		content_width := panel_width - i32(shadow_padding_x) * 2
		content_height := panel_height - i32(shadow_padding_y) * 2
		content_rect := sdl.FRect {
			x = panel_x + shadow_padding_x,
			y = panel_y + shadow_padding_y,
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
		assert(
			ttf.SetTextColor(input_text, text_color.r, text_color.g, text_color.b, text_color.a),
		)

		apps, err := get_installed_apps_info()
		if err.message != "" {
			fmt.println(err.message)
			return
		}

		defer destroy_installed_apps(apps)

		icon_theme := active_icon_theme()
		defer delete(icon_theme)
		application_icon_textures := make([]^sdl.Texture, len(apps))
		defer delete(application_icon_textures)
		application_icon_lookups := make([]bool, len(apps))
		defer delete(application_icon_lookups)

		fallback_icon_texture: ^sdl.Texture
		fallback_icon_path := resolve_icon_path(ICON_FALLBACK_NAME, icon_theme)
		if fallback_icon_path != nil {
			fallback_icon_texture = image.LoadTexture(renderer, fallback_icon_path)
			delete(fallback_icon_path)
			if fallback_icon_texture != nil {
				_ = sdl.SetTextureScaleMode(fallback_icon_texture, .LINEAR)
			}
		}
		defer {
			for texture in application_icon_textures {
				if texture != nil {
					sdl.DestroyTexture(texture)
				}
			}

			if fallback_icon_texture != nil {
				sdl.DestroyTexture(fallback_icon_texture)
			}
		}

		application_name_texts := make([]^ttf.Text, len(apps))
		defer delete(application_name_texts)
		application_description_texts := make([]^ttf.Text, len(apps))
		defer delete(application_description_texts)
		for application, index in apps {
			application_name_texts[index] = create_colored_text(
				text_engine,
				list_name_font,
				application.name,
				text_color,
			)
			assert(application_name_texts[index] != nil)
			list_subtitle: cstring = ""
			if application.generic_name != nil && len(application.generic_name) > 0 {
				list_subtitle = application.generic_name
			} else if application.description != nil {
				list_subtitle = application.description
			}

			application_description_texts[index] = create_colored_text(
				text_engine,
				list_description_font,
				list_subtitle,
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

		filtered_app_indices := search_apps(apps[:], "")
		defer {
			delete(filtered_app_indices)
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

		// input.
		input_x := panel_x + shadow_padding_x + 4 * render_scale_x
		input_y := panel_y + shadow_padding_y + 4 * render_scale_y
		input_width := f32(content_width) - 8 * render_scale_x
		input_height := INPUT_HEIGHT * render_scale_y

		input_surface_config := Rounded_Input_Surface {
			width        = i32(input_width),
			height       = i32(input_height),
			radius       = i32(f32(INPUT_RADIUS) * render_scale_y),
			border_width = i32(f32(WINDOW_BORDER_WIDTH) * render_scale_y),
			border_color = input_border_color,
			background   = app_color,
		}
		input_surface := rounded_input_surface(input_surface_config)
		assert(input_surface != nil)
		input_texture := sdl.CreateTextureFromSurface(renderer, input_surface)
		sdl.DestroySurface(input_surface)
		assert(input_texture != nil)
		defer sdl.DestroyTexture(input_texture)

		input_inactive_config := input_surface_config
		input_inactive_config.border_color = window_border_color
		input_inactive_surface := rounded_input_surface(input_inactive_config)
		assert(input_inactive_surface != nil)
		input_inactive_texture := sdl.CreateTextureFromSurface(renderer, input_inactive_surface)
		sdl.DestroySurface(input_inactive_surface)
		assert(input_inactive_texture != nil)
		defer sdl.DestroyTexture(input_inactive_texture)

		input_rect := sdl.FRect {
			x = input_x,
			y = input_y,
			w = input_width,
			h = input_height,
		}

		// list.
		list_x := input_x
		list_y := input_y + input_height + 4 * render_scale_y
		list_width := input_width
		list_height :=
			panel_y + shadow_padding_y + f32(content_height) - 4 * render_scale_y - list_y
		row_height := list_font_size * LIST_ROW_HEIGHT_RATIO * render_scale_y
		visible_row_count := max(1, int(list_height / row_height))
		row_height = list_height / f32(visible_row_count)
		max_scroll_offset := max(0, len(filtered_app_indices) - visible_row_count)
		list_clip := sdl.Rect {
			x = i32(list_x),
			y = i32(list_y),
			w = i32(list_width),
			h = i32(list_height),
		}

		highlight_height := row_height - 1 * render_scale_y
		highlight_config := Rounded_Input_Surface {
			width        = i32(list_width),
			height       = i32(highlight_height),
			radius       = i32(f32(LIST_HIGHLIGHT_RADIUS) * render_scale_y),
			border_width = 0,
			border_color = selected_color,
			background   = selected_color,
		}
		highlight_surface := rounded_input_surface(highlight_config)
		assert(highlight_surface != nil)
		highlight_texture := sdl.CreateTextureFromSurface(renderer, highlight_surface)
		sdl.DestroySurface(highlight_surface)
		assert(highlight_texture != nil)
		defer sdl.DestroyTexture(highlight_texture)

		hover_config := highlight_config
		hover_config.border_color = hover_color
		hover_config.background = hover_color
		hover_surface := rounded_input_surface(hover_config)
		assert(hover_surface != nil)
		hover_texture := sdl.CreateTextureFromSurface(renderer, hover_surface)
		sdl.DestroySurface(hover_surface)
		assert(hover_texture != nil)
		defer sdl.DestroyTexture(hover_texture)

		input: strings.Builder
		strings.builder_init(&input, 0, 256)
		defer strings.builder_destroy(&input)

		assert(sdl.StartTextInput(window))
		defer _ = sdl.StopTextInput(window)

		input_dirty := true
		search_dirty := false
		caret_state: Caret_State
		selected_index := 0
		scroll_offset := 0
		last_wheel_scroll_at: u64
		mouse_x, mouse_y: f32
		has_mouse_position := false
		window_shown := false
		has_focus := false
		running := true

		for running {
			if poll_toggle_signal(toggle_server) {
				running = false
				break
			}

			when ODIN_OS == .Linux {
				if layer_shell_state != nil {
					if vima_layer_shell_closed(layer_shell_state) != 0 {
						break
					}
					configured_width := i32(vima_layer_shell_width(layer_shell_state))
					configured_height := i32(vima_layer_shell_height(layer_shell_state))
					if configured_width != window_width || configured_height != window_height {
						assert(sdl.SetWindowSize(window, configured_width, configured_height))
						rebuild_ui = true
						break
					}
				}
			}

			e: sdl.Event

			for sdl.PollEvent(&e) {
				#partial switch e.type {
				case .SYSTEM_THEME_CHANGED:
					apply_system_theme()
					rebuild_ui = true
					running = false

				case .KEY_DOWN:
					#partial switch e.key.scancode {
					case .ESCAPE:
						running = false
						break

					case .RETURN, .KP_ENTER:
						if len(filtered_app_indices) > 0 &&
						   selected_index >= 0 &&
						   selected_index < len(filtered_app_indices) {
							app_index := filtered_app_indices[selected_index]
							if apps[app_index].exec != nil &&
							   launch_app(string(apps[app_index].exec)) {
								running = false
							} else if apps[app_index].exec != nil {
								fmt.eprintln("Failed to launch ", apps[app_index].name)
							}
						}
						break

					case .UP:
						selected_index = max(0, selected_index - 1)
						break

					case .DOWN:
						if len(filtered_app_indices) > 0 {
							selected_index = min(len(filtered_app_indices) - 1, selected_index + 1)
						}
						break

					case .PAGEUP:
						selected_index = max(0, selected_index - visible_row_count)
						break

					case .PAGEDOWN:
						if len(filtered_app_indices) > 0 {
							selected_index = min(
								len(filtered_app_indices) - 1,
								selected_index + visible_row_count,
							)
						}
						break

					case .BACKSPACE:
						_, _ = strings.pop_rune(&input)
						input_dirty = true
						search_dirty = true
						caret_state.last_input_at = sdl.GetTicks()
						caret_state.has_input_activity = true
						break
					}

				case .TEXT_INPUT:
					strings.write_string(&input, string(e.text.text))
					input_dirty = true
					search_dirty = true
					caret_state.last_input_at = sdl.GetTicks()
					caret_state.has_input_activity = true

				case .MOUSE_WHEEL:
					now := sdl.GetTicks()
					if len(filtered_app_indices) > 0 &&
					   e.wheel.y != 0 &&
					   (last_wheel_scroll_at == 0 ||
							   now - last_wheel_scroll_at >= WHEEL_SCROLL_INTERVAL) {
						direction := -1 if e.wheel.y > 0 else 1
						selected_index = clamp(
							selected_index + direction,
							0,
							len(filtered_app_indices) - 1,
						)
						last_wheel_scroll_at = now
					}

				case .MOUSE_MOTION:
					mouse_x = e.motion.x * pixel_scale_x
					mouse_y = e.motion.y * pixel_scale_y
					has_mouse_position = true

				case .MOUSE_BUTTON_DOWN:
					if e.button.button == sdl.BUTTON_LEFT {
						mouse_x = e.button.x * pixel_scale_x
						mouse_y = e.button.y * pixel_scale_y
						has_mouse_position = true
						if layer_shell_mode &&
						   (mouse_x < panel_x ||
								   mouse_x >= panel_x + f32(panel_width) ||
								   mouse_y < panel_y ||
								   mouse_y >= panel_y + f32(panel_height)) {
							running = false
						} else if mouse_x >= list_x &&
						   mouse_x < list_x + list_width &&
						   mouse_y >= list_y &&
						   mouse_y < list_y + list_height {
							visible_index := int((mouse_y - list_y) / row_height)
							clicked_index := scroll_offset + visible_index
							if clicked_index < len(filtered_app_indices) &&
							   visible_index < visible_row_count {
								selected_index = clicked_index
								app_index := filtered_app_indices[clicked_index]
								if apps[app_index].exec != nil {
									if launch_app(string(apps[app_index].exec)) {
										running = false
									} else {
										fmt.eprintln("Failed to launch ", apps[app_index].name)
									}
								}
							}
						}
					}

				case .WINDOW_FOCUS_GAINED:
					if e.window.windowID == window_id {
						has_focus = true
					}

				case .WINDOW_FOCUS_LOST:
					if e.window.windowID == window_id && has_focus {
						running = false
					}

				case .WINDOW_DISPLAY_SCALE_CHANGED, .WINDOW_PIXEL_SIZE_CHANGED:
					if e.window.windowID != window_id {
						break
					}
					current_render_width, current_render_height: i32
					if sdl.GetCurrentRenderOutputSize(
						   renderer,
						   &current_render_width,
						   &current_render_height,
					   ) &&
					   (current_render_width != render_width ||
							   current_render_height != render_height ||
							   abs(sdl.GetWindowDisplayScale(window) - initial_display_scale) >
								   0.001 ||
							   abs(sdl.GetWindowPixelDensity(window) - initial_pixel_density) >
								   0.001) {
						requested_display_scale = sdl.GetWindowDisplayScale(window)
						rebuild_ui = true
						running = false
					}

				case .QUIT:
					running = false
				}

				if !running {
					break
				}
			}

			if search_dirty {
				delete(filtered_app_indices)
				filtered_app_indices = search_apps(apps[:], strings.to_string(input))
				selected_index = 0
				scroll_offset = 0
				max_scroll_offset = max(0, len(filtered_app_indices) - visible_row_count)
				search_dirty = false
			}

			if selected_index < scroll_offset {
				scroll_offset = selected_index
			} else if selected_index >= scroll_offset + visible_row_count {
				scroll_offset = selected_index - visible_row_count + 1
			}
			scroll_offset = min(scroll_offset, max_scroll_offset)

			sdl.SetRenderDrawColor(renderer, 0, 0, 0, 0)
			sdl.RenderClear(renderer)
			sdl.RenderTexture(renderer, backdrop_texture, nil, &panel_rect)

			current_input_texture := input_inactive_texture
			if has_focus {
				current_input_texture = input_texture
			}
			sdl.RenderTexture(renderer, current_input_texture, nil, &input_rect)

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
			hovered_index := -1
			if has_mouse_position &&
			   mouse_x >= list_x && mouse_x < list_x + list_width &&
			   mouse_y >= list_y && mouse_y < list_y + list_height {
				visible_index := int((mouse_y - list_y) / row_height)
				candidate_index := scroll_offset + visible_index
				if visible_index < visible_row_count && candidate_index < len(filtered_app_indices) {
					hovered_index = candidate_index
				}
			}

			visible_end := min(len(filtered_app_indices), scroll_offset + visible_row_count)
			for application_index in scroll_offset ..< visible_end {
				source_index := filtered_app_indices[application_index]
				visible_index := application_index - scroll_offset
				row_y := list_y + f32(visible_index) * row_height

				if application_index == selected_index {
					selected_rect := sdl.FRect {
						x = list_x,
						y = row_y,
						w = list_width,
						h = highlight_height,
					}

					sdl.RenderTexture(renderer, highlight_texture, nil, &selected_rect)
				} else if application_index == hovered_index {
					hover_rect := sdl.FRect {
						x = list_x,
						y = row_y,
						w = list_width,
						h = highlight_height,
					}
					sdl.RenderTexture(renderer, hover_texture, nil, &hover_rect)
				}

				name_color := text_color
				description_color := subtext_color
				if application_index == selected_index {
					name_color = selected_text_color
					description_color = selected_text_color
				}
				assert(
					ttf.SetTextColor(
						application_name_texts[source_index],
						name_color.r,
						name_color.g,
						name_color.b,
						name_color.a,
					),
				)
				assert(
					ttf.SetTextColor(
						application_description_texts[source_index],
						description_color.r,
						description_color.g,
						description_color.b,
						description_color.a,
					),
				)

				row_text_x := list_x + 10 * render_scale_x
				name_width: i32
				assert(ttf.GetTextSize(application_name_texts[source_index], &name_width, nil))
				assert(
					ttf.DrawRendererText(
						application_name_texts[source_index],
						row_text_x,
						row_y + (row_height - f32(list_name_height)) / 2,
					),
				)
				assert(
					ttf.DrawRendererText(
						application_description_texts[source_index],
						row_text_x + f32(name_width) + 8 * render_scale_x,
						row_y + (row_height - f32(list_description_height)) / 2,
					),
				)

				if !application_icon_lookups[source_index] {
					application_icon_lookups[source_index] = true
					icon_path := resolve_icon_path(apps[source_index].icon, icon_theme)
					if icon_path != nil {
						application_icon_textures[source_index] = image.LoadTexture(
							renderer,
							icon_path,
						)
						delete(icon_path)
						if application_icon_textures[source_index] != nil {
							_ = sdl.SetTextureScaleMode(
								application_icon_textures[source_index],
								.LINEAR,
							)
						}
					}
				}

				icon_texture := application_icon_textures[source_index]
				if icon_texture == nil {
					icon_texture = fallback_icon_texture
				}
				if icon_texture != nil {
					icon_size := min(
						LIST_ICON_SIZE * render_scale_y,
						row_height - 8 * render_scale_y,
					)
					icon_rect := sdl.FRect {
						x = list_x + list_width - icon_size - 10 * render_scale_x,
						y = row_y + (row_height - icon_size) / 2,
						w = icon_size,
						h = icon_size,
					}
					sdl.RenderTexture(renderer, icon_texture, nil, &icon_rect)
				}

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

			if !window_shown {
				assert(sdl.ShowWindow(window))
				if !layer_shell_mode {
					_ = sdl.RaiseWindow(window)
				}
				_ = sdl.SyncWindow(window)
				window_shown = true
			}
		}
	}
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

create_colored_text :: proc(
	text_engine: ^ttf.TextEngine,
	font: ^ttf.Font,
	value: cstring,
	color: Color,
) -> ^ttf.Text {
	text := ttf.CreateText(text_engine, font, value, c.size_t(len(value)))
	if text == nil {
		return nil
	}

	if !ttf.SetTextColor(text, color.r, color.g, color.b, color.a) {
		ttf.DestroyText(text)
		return nil
	}
	return text
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
			fx := f32(x) + 0.5
			fy := f32(y) + 0.5

			outer_d := rounded_rect_sdf(fx, fy, f32(width), f32(height), f32(radius))
			inner_d := rounded_rect_sdf(
				fx - f32(border_width),
				fy - f32(border_width),
				f32(width - border_width * 2),
				f32(height - border_width * 2),
				f32(inner_radius),
			)

			outer_cov := coverage(outer_d)
			inner_cov := coverage(inner_d)
			ring_cov := clamp(outer_cov - inner_cov, 0, 1)

			alpha := u8(ring_cov * 255)
			if !sdl.WriteSurfacePixel(border, x, y, color.r, color.g, color.b, alpha) {
				sdl.DestroySurface(border)
				return nil
			}
		}
	}

	return border
}

Rounded_Input_Surface :: struct {
	width:        i32,
	height:       i32,
	radius:       i32,
	border_width: i32,
	border_color: Color,
	background:   Color,
}

rounded_input_surface :: proc(config: Rounded_Input_Surface) -> ^sdl.Surface {
	width := config.width
	height := config.height
	radius := config.radius
	border_width := config.border_width
	border_color := config.border_color
	background := config.background

	surface := sdl.CreateSurface(width, height, .RGBA8888)
	if surface == nil {
		return nil
	}
	inner_radius := radius - border_width
	if inner_radius < 0 {
		inner_radius = 0
	}

	bg := [4]f32 {
		f32(background.r) / 255,
		f32(background.g) / 255,
		f32(background.b) / 255,
		f32(background.a) / 255,
	}
	bd := [4]f32 {
		f32(border_color.r) / 255,
		f32(border_color.g) / 255,
		f32(border_color.b) / 255,
		f32(border_color.a) / 255,
	}

	for y in 0 ..< height {
		for x in 0 ..< width {
			fx := f32(x) + 0.5
			fy := f32(y) + 0.5

			outer_d := rounded_rect_sdf(fx, fy, f32(width), f32(height), f32(radius))
			inner_d := rounded_rect_sdf(
				fx - f32(border_width),
				fy - f32(border_width),
				f32(width - border_width * 2),
				f32(height - border_width * 2),
				f32(inner_radius),
			)

			outer_cov := coverage(outer_d)
			inner_cov := coverage(inner_d)

			// layer 1: border, masked by outer shape, over transparent
			border_layer := [4]f32{bd.r, bd.g, bd.b, bd.a * outer_cov}
			result := composite_over(border_layer, {0, 0, 0, 0})

			// layer 2: background, masked by inner shape, over border layer
			bg_layer := [4]f32{bg.r, bg.g, bg.b, bg.a * inner_cov}
			result = composite_over(bg_layer, result)

			r := u8(clamp(result.r, 0, 1) * 255)
			g := u8(clamp(result.g, 0, 1) * 255)
			b := u8(clamp(result.b, 0, 1) * 255)
			a := u8(clamp(result.a, 0, 1) * 255)

			if !sdl.WriteSurfacePixel(surface, x, y, r, g, b, a) {
				sdl.DestroySurface(surface)
				return nil
			}
		}
	}
	return surface
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

// signed distance from point to rounded-rect edge; negative = inside
rounded_rect_sdf :: proc(x, y, width, height, radius: f32) -> f32 {
	// distance from center, clamped into the "core" rect shrunk by radius
	cx := width / 2
	cy := height / 2
	qx := abs(x - cx) - (cx - radius)
	qy := abs(y - cy) - (cy - radius)
	outside := math.sqrt(max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0))
	inside := min(max(qx, qy), 0)
	return outside + inside - radius
}

coverage :: proc(dist: f32) -> f32 {
	// smoothstep over ~1px band around the edge
	return clamp(0.5 - dist, 0, 1)
}

// standard "src over dst" alpha compositing
composite_over :: proc(src: [4]f32, dst: [4]f32) -> [4]f32 {
	out_a := src.a + dst.a * (1 - src.a)
	if out_a <= 0 {
		return {0, 0, 0, 0}
	}
	out_rgb := (src.rgb * src.a + dst.rgb * dst.a * (1 - src.a)) / out_a
	return {out_rgb.r, out_rgb.g, out_rgb.b, out_a}
}
