:- use_module('../prolog/sshfling').

:- initialization(main, main).

main([SmokeDirectory]) :-
    sshfling:run(["--version"], 0),
    sshfling:run(["init", SmokeDirectory, "--force", "--session-seconds", "60"], 0),
    directory_file_path(SmokeDirectory, 'production/sshfling-session', SessionWrapper),
    exists_file(SessionWrapper),
    !.
main(_) :-
    halt(1).
