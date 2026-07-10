-module(sshfling_ffi).
-export([run/1, runtime_path/0, template_directory/0]).

configured(Name, Default) ->
    case os:getenv(Name) of false -> Default; "" -> Default; Value -> Value end.

root() ->
    case os:getenv("SSHFLING_PACKAGE_ROOT") of
        false ->
            case code:priv_dir(sshfling) of
                {error, bad_name} -> filename:absname("priv/runtime");
                Priv -> filename:join(Priv, "runtime")
            end;
        "" ->
            case code:priv_dir(sshfling) of
                {error, bad_name} -> filename:absname("priv/runtime");
                Priv -> filename:join(Priv, "runtime")
            end;
        PackageRoot -> filename:join(PackageRoot, "priv/runtime")
    end.

runtime_path() ->
    configured("SSHFLING_RUNTIME", filename:join(root(), "sshfling.py")).

template_directory() ->
    configured("SSHFLING_TEMPLATE_DIR", filename:join(root(), "templates")).

executable(Python) ->
    case filename:pathtype(Python) of
        absolute -> Python;
        _ -> os:find_executable(Python)
    end.

run(Arguments) ->
    Python = configured("SSHFLING_PYTHON", "python3"),
    Runtime = runtime_path(),
    case {filelib:is_regular(Runtime), executable(Python)} of
        {false, _} -> 127;
        {_, false} -> 127;
        {true, Program} ->
            Port = open_port(
                {spawn_executable, Program},
                [binary, exit_status, use_stdio, stderr_to_stdout,
                 {args, [Runtime | Arguments]},
                 {env, [{"SSHFLING_TEMPLATE_DIR", template_directory()},
                        {"PYTHONUNBUFFERED", "1"}]}]),
            wait(Port)
    end.

wait(Port) ->
    receive
        {Port, {data, Data}} -> io:put_chars(Data), wait(Port);
        {Port, {exit_status, Status}} -> Status
    end.
