package main

import "core:os"
import "core:strconv"
import "core:strings"

DEFAULT_SYSTEM_FONT_SIZE :: 13.0

system_font_size :: proc() -> f32 {
	when ODIN_OS == .Linux {
		state, stdout, stderr, err := os.process_exec(
			os.Process_Desc {
				command = []string {
					"kreadconfig6",
					"--file",
					"kdeglobals",
					"--group",
					"General",
					"--key",
					"font",
				},
			},
			context.allocator,
		)
		defer delete(stdout)
		defer delete(stderr)

		if err == nil && state.success {
			font_setting := strings.trim_space(string(stdout))
			field_index := 0
			for field in strings.split_by_byte_iterator(&font_setting, ',') {
				if field_index == 1 {
					size, ok := strconv.parse_f32(strings.trim_space(field))
					if ok && size >= 6 && size <= 72 {
						return size
					}
					break
				}
				field_index += 1
			}
		}
	}

	return DEFAULT_SYSTEM_FONT_SIZE
}
