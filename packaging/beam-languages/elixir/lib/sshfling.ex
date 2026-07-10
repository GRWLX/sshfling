defmodule SSHFling do
  @moduledoc "Launcher API for the bundled SSHFling runtime."

  @spec runtime_path() :: String.t()
  def runtime_path do
    configured_or("SSHFLING_RUNTIME", Application.app_dir(:sshfling, "priv/runtime/sshfling.py"))
  end

  @spec template_directory() :: String.t()
  def template_directory do
    configured_or("SSHFLING_TEMPLATE_DIR", Application.app_dir(:sshfling, "priv/runtime/templates"))
  end

  @spec run([String.t()]) :: non_neg_integer()
  def run(arguments) when is_list(arguments) do
    if Enum.all?(arguments, &is_binary/1) do
      python = configured_or("SSHFLING_PYTHON", "python3")
      runtime = runtime_path()

      if not File.regular?(runtime) do
        127
      else
        try do
        {_output, status} =
          System.cmd(python, [runtime | arguments],
            env: [
              {"SSHFLING_TEMPLATE_DIR", template_directory()},
              {"PYTHONUNBUFFERED", "1"}
            ],
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

          status
        rescue
          error in ErlangError ->
            IO.puts(:stderr, "sshfling: #{Exception.message(error)}")
            127
        end
      end
    else
      raise ArgumentError, "SSHFling arguments must all be strings"
    end
  end

  defp configured_or(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> value
    end
  end
end
