package calculator

TOKEN :: enum {
	PLUS     = "+",
	MINUS    = "-",
	MULTIPLY = "*",
	DIVIDE   = "/",
	POWER    = "^",
}

tokenize :: proc(input: string) -> []TOKEN {

}

AST :: struct {}

parse :: proc(input: string) -> []AST {

}
