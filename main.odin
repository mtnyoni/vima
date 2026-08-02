package main

import "core:fmt"
import "core:os"
import "core:strings"

main :: proc() {
	args := os.args
	title_value := "Vima"
	if len(args) > 1 {
		title_value = args[1]
	}

	title: cstring = strings.clone_to_cstring(title_value)
	defer delete(title)
	main_window(title)
}
