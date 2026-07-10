@module("sshfling")
external run: array<string> => int = "run"

@module("sshfling")
external templateDir: unit => string = "templateDir"

// This binding targets CommonJS on Node and is not a browser binding.
let status = run(["--version"])
let templates = templateDir()
