defmodule SSHFlingConsumerTest do
  use ExUnit.Case, async: false

  test "consumer invokes the API and initializes bundled templates" do
    smoke_directory = System.fetch_env!("SSHFLING_SMOKE_PROJECT")
    assert SSHFling.run(["--version"]) == 0
    assert SSHFling.run(["init", smoke_directory, "--force", "--session-seconds", "60"]) == 0
    assert File.regular?(Path.join(smoke_directory, "production/sshfling-session"))
  end
end
