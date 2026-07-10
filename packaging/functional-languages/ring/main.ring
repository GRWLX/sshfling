load "lib.ring"

func main
    nStatus = run(sysargv[3:len(sysargv)])
    if nStatus != 0
        raise("SSHFling exited with status " + nStatus)
    ok
