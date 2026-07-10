load "lib.ring"

func commandarguments
    aArgs = []
    if len(sysargv) >= 3
        for nIndex = 3 to len(sysargv) add(aArgs, sysargv[nIndex]) next
    ok
    return aArgs

func main
    nStatus = run(commandarguments())
    cStatusFile = sysget("SSHFLING_RING_STATUS_FILE")
    if cStatusFile != "" write(cStatusFile, "" + nStatus) ok
