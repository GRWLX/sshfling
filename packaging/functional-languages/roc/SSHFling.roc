module [run!, runtime_path!, template_directory!, package_version]

import cli.Cmd
import cli.Env
import cli.File

package_version = "0.0.0"

configured_or! = |name, fallback|
    Env.var!(name)
    |> Result.with_default(fallback)

runtime_path! = |_|
    configured_or!("SSHFLING_RUNTIME", "runtime/sshfling.py")

template_directory! = |_|
    configured_or!("SSHFLING_TEMPLATE_DIR", "runtime/templates")

run! : List Str => Result I32 _
run! = |args|
    python = configured_or!("SSHFLING_PYTHON", "python3")
    runtime = runtime_path!({})
    templates = template_directory!({})

    if File.exists!(runtime)? then
        Cmd.new(python)
        |> Cmd.args(List.prepend(args, runtime))
        |> Cmd.env("SSHFLING_TEMPLATE_DIR", templates)
        |> Cmd.env("PYTHONUNBUFFERED", "1")
        |> Cmd.exec_exit_code!()
    else
        Ok(127)
