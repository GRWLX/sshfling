#Requires AutoHotkey v2.0
; SPDX-License-Identifier: MIT
#Include "SSHFling.ahk"

if A_Args.Length = 1 && A_Args[1] = "--self-test" {
    status := SSHFling.Run(["/D", "/C", "exit 23"], A_ComSpec)
    ExitApp(status = 23 ? 0 : 1)
}

ExitApp(SSHFling.Run(A_Args))
