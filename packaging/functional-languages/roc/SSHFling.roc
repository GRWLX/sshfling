module [run!, runtime_path!, template_directory!]

import cli.Cmd
import cli.Env

package_version = "0.0.0"

configured_or! = |name, fallback|
    Env.var!(name)
    |> Result.with_default(fallback)

runtime_path! = ||
    configured_or!("SSHFLING_RUNTIME", "runtime/sshfling.py")

template_directory! = ||
    configured_or!("SSHFLING_TEMPLATE_DIR", "runtime/templates")

run! : List Str => Result I32 _
run! = |args|
    python = configured_or!("SSHFLING_PYTHON", "python3")
    runtime = runtime_path!()
    templates = template_directory!()

    Cmd.new(python)
    |> Cmd.args(List.prepend(args, runtime))
    |> Cmd.env("SSHFLING_TEMPLATE_DIR", templates)
    |> Cmd.env("PYTHONUNBUFFERED", "1")
    |> Cmd.exec_exit_code!()
