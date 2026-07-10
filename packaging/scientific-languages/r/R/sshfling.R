configured_or <- function(name, default) {
  value <- Sys.getenv(name, unset = "")
  if (nzchar(value)) value else default
}

#' Return the installed canonical SSHFling runtime path.
#' @export
runtime_path <- function() {
  configured <- Sys.getenv("SSHFLING_RUNTIME", unset = "")
  if (nzchar(configured)) {
    return(configured)
  }
  installed <- system.file("runtime", "sshfling.py", package = "sshfling")
  if (nzchar(installed)) {
    return(installed)
  }
  file.path(getwd(), "inst", "runtime", "sshfling.py")
}

#' Return the installed SSHFling template directory.
#' @export
template_directory <- function() {
  configured <- Sys.getenv("SSHFLING_TEMPLATE_DIR", unset = "")
  if (nzchar(configured)) {
    return(configured)
  }
  installed <- system.file("runtime", "templates", package = "sshfling")
  if (nzchar(installed)) {
    return(installed)
  }
  file.path(getwd(), "inst", "runtime", "templates")
}

#' Run SSHFling and return its process status.
#' @param args A character vector of command-line arguments.
#' @export
run <- function(args = character()) {
  stopifnot(is.character(args), !anyNA(args))
  runtime <- runtime_path()
  if (!file.exists(runtime)) {
    return(127L)
  }
  python <- configured_or("SSHFLING_PYTHON", "python3")
  old_template <- Sys.getenv("SSHFLING_TEMPLATE_DIR", unset = NA_character_)
  old_unbuffered <- Sys.getenv("PYTHONUNBUFFERED", unset = NA_character_)
  on.exit({
    if (is.na(old_template)) Sys.unsetenv("SSHFLING_TEMPLATE_DIR") else Sys.setenv(SSHFLING_TEMPLATE_DIR = old_template)
    if (is.na(old_unbuffered)) Sys.unsetenv("PYTHONUNBUFFERED") else Sys.setenv(PYTHONUNBUFFERED = old_unbuffered)
  }, add = TRUE)
  Sys.setenv(SSHFLING_TEMPLATE_DIR = template_directory(), PYTHONUNBUFFERED = "1")
  status <- tryCatch(
    system2(python, shQuote(c(runtime, args)), stdout = "", stderr = ""),
    error = function(error) {
      message("sshfling: ", conditionMessage(error))
      127L
    }
  )
  if (is.null(status)) 0L else as.integer(status)
}
