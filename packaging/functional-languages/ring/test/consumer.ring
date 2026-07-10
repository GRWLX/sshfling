load "../lib.ring"

func main
    cSmoke = sysargv[3]
    if run(["--version"]) != 0 raise("version failed") ok
    if run(["--definitely-invalid"]) != 2 raise("invalid option failed") ok
    if run(["init", cSmoke, "--force", "--session-seconds", "60"]) != 0
        raise("init failed")
    ok
