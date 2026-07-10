#Requires AutoHotkey v2.0
; SPDX-License-Identifier: MIT

; Unpublished launcher candidate. Run() starts a real child process and returns
; its exit code. Windows command-line quoting follows the backslash-before-quote
; rules used by CommandLineToArgvW-compatible programs.
class SSHFling {
    static Run(arguments := [], executable := "") {
        if !(arguments is Array)
            throw TypeError("SSHFling arguments must be an Array")

        if executable = "" {
            executable := EnvGet("SSHFLING_EXECUTABLE")
            if executable = ""
                executable := "sshfling.exe"
        }
        SSHFling.ValidateText(executable, "executable")

        commandLine := SSHFling.QuoteWindowsArgument(executable)
        for index, argument in arguments {
            SSHFling.ValidateText(argument, "argument " index)
            commandLine .= " " SSHFling.QuoteWindowsArgument(argument)
        }

        try
            return RunWait(commandLine)
        catch as launchError
            throw Error("Could not start SSHFling: " launchError.Message, -1, launchError.Extra)
    }

    static ValidateText(value, label) {
        if Type(value) != "String"
            throw TypeError(label " must be a String")
        if InStr(value, Chr(0))
            throw ValueError(label " contains a NUL character")
    }

    static QuoteWindowsArgument(value) {
        quote := Chr(34)
        slash := Chr(92)
        result := quote
        slashCount := 0

        Loop Parse value {
            character := A_LoopField
            if character = slash {
                slashCount += 1
            } else if character = quote {
                result .= SSHFling.Repeat(slash, slashCount * 2 + 1) quote
                slashCount := 0
            } else {
                result .= SSHFling.Repeat(slash, slashCount) character
                slashCount := 0
            }
        }
        return result SSHFling.Repeat(slash, slashCount * 2) quote
    }

    static Repeat(value, count) {
        result := ""
        Loop count
            result .= value
        return result
    }
}
