using SSHFling
using Test

smoke = get(ENV, "SSHFLING_SMOKE_PROJECT", mktempdir())
@test SSHFling.run(["--version"]) == 0
@test SSHFling.run(["init", smoke, "--force", "--session-seconds", "60"]) == 0
@test isfile(joinpath(smoke, "production", "sshfling-session"))
