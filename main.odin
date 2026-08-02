package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	args := os.args
	if len(args) == 0 {
		return
	}

	title: cstring = strings.clone_to_cstring(args[1])
	defer delete(title)
	main_window(title)
}
