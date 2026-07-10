BEGIN {
    sshfling_cli_argc = 0
    for (sshfling_cli_i = 1; sshfling_cli_i < ARGC; sshfling_cli_i++) {
        sshfling_cli_argv[++sshfling_cli_argc] = ARGV[sshfling_cli_i]
        delete ARGV[sshfling_cli_i]
    }
    exit sshfling_run(sshfling_cli_argv, sshfling_cli_argc)
}
