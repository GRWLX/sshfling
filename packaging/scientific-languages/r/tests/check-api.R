library(sshfling)

stopifnot(identical(run(c("--version")), 0L))
stopifnot(identical(run(c("--definitely-invalid")), 2L))

smoke_directory <- tempfile("sshfling-r-check-")
stopifnot(identical(
  run(c("init", smoke_directory, "--force", "--session-seconds", "60")),
  0L
))
stopifnot(file.exists(file.path(smoke_directory, "production", "sshfling-session")))
stopifnot(file.access(file.path(smoke_directory, "production", "sshfling-session"), 1L) == 0L)
stopifnot(file.exists(file.path(smoke_directory, "secrets", ".gitkeep")))
unlink(smoke_directory, recursive = TRUE)

old_runtime <- Sys.getenv("SSHFLING_RUNTIME", unset = NA_character_)
Sys.setenv(SSHFLING_RUNTIME = file.path(tempdir(), "missing-sshfling.py"))
stopifnot(identical(run(character()), 127L))
if (is.na(old_runtime)) Sys.unsetenv("SSHFLING_RUNTIME") else Sys.setenv(SSHFLING_RUNTIME = old_runtime)
