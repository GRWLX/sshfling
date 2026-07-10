-module(sshfling_consumer).

-export([run/1]).

-spec run(string()) -> ok.
run(SmokeDirectory) ->
    0 = sshfling:run(["--version"]),
    0 = sshfling:run(["init", SmokeDirectory, "--force", "--session-seconds", "60"]),
    true = filelib:is_regular(filename:join([SmokeDirectory, "production", "sshfling-session"])),
    ok.
