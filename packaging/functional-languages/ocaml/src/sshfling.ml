let configured_or name fallback =
  match Sys.getenv_opt name with
  | Some value when value <> "" -> value
  | _ -> fallback ()

let package_root () =
  match Sys.getenv_opt "SSHFLING_PACKAGE_ROOT" with
  | Some value when value <> "" -> Filename.concat value "runtime"
  | _ -> Runtime_config.resource_root

let runtime_path () =
  configured_or "SSHFLING_RUNTIME" (fun () ->
      Filename.concat (package_root ()) "sshfling.py")

let template_directory () =
  configured_or "SSHFLING_TEMPLATE_DIR" (fun () ->
      Filename.concat (package_root ()) "templates")

let replace_environment name value environment =
  let prefix = name ^ "=" in
  let inherited =
    environment
    |> Array.to_list
    |> List.filter (fun item -> not (String.starts_with ~prefix item))
  in
  Array.of_list ((prefix ^ value) :: inherited)

let status_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal -> 128 + signal
  | Unix.WSTOPPED signal -> 128 + signal

let run arguments =
  let runtime = runtime_path () in
  if not (Sys.file_exists runtime) then 127
  else
    let python = configured_or "SSHFLING_PYTHON" (fun () -> "python3") in
    let argv = Array.of_list (python :: runtime :: arguments) in
    let environment =
      Unix.environment ()
      |> replace_environment "SSHFLING_TEMPLATE_DIR" (template_directory ())
      |> replace_environment "PYTHONUNBUFFERED" "1"
    in
    try
      let pid =
        Unix.create_process_env python argv environment Unix.stdin Unix.stdout
          Unix.stderr
      in
      let _, status = Unix.waitpid [] pid in
      status_code status
    with Unix.Unix_error (Unix.ENOENT, _, _) -> 127
