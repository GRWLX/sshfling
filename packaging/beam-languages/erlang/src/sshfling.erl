-module(sshfling).

-export([run/1, runtime_path/0, template_directory/0]).

-spec environment_or_default(string(), string()) -> string().
environment_or_default(Name, Default) ->
    case os:getenv(Name) of
        false -> Default;
        "" -> Default;
        Value -> Value
    end.

-spec package_root() -> file:filename_all().
package_root() ->
    case os:getenv("SSHFLING_PACKAGE_ROOT") of
        false ->
            case code:priv_dir(sshfling) of
                {error, bad_name} -> filename:absname(".");
                Priv -> filename:dirname(Priv)
            end;
        "" -> filename:absname(".");
        Root -> Root
    end.

-spec runtime_path() -> file:filename_all().
runtime_path() ->
    environment_or_default(
      "SSHFLING_RUNTIME",
      filename:join([package_root(), "priv", "runtime", "sshfling.py"])).

-spec template_directory() -> file:filename_all().
template_directory() ->
    environment_or_default(
      "SSHFLING_TEMPLATE_DIR",
      filename:join([package_root(), "priv", "runtime", "templates"])).

-spec executable(string()) -> string() | false.
executable(Python) ->
    case filename:pathtype(Python) of
        absolute -> Python;
        _ -> os:find_executable(Python)
    end.

-spec run([string()]) -> non_neg_integer().
run(Arguments) when is_list(Arguments) ->
    true = lists:all(fun is_list/1, Arguments),
    Python = environment_or_default("SSHFLING_PYTHON", "python3"),
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
            wait_for_exit(Port)
    end.

-spec wait_for_exit(port()) -> non_neg_integer().
wait_for_exit(Port) ->
    receive
        {Port, {data, Data}} ->
            ok = io:put_chars(Data),
            wait_for_exit(Port);
        {Port, {exit_status, Status}} ->
            Status
    end.
