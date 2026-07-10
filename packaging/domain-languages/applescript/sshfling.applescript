-- SPDX-License-Identifier: MIT
-- Unpublished launcher candidate. AppleScript's `do shell script` captures
-- output and cannot service an interactive stdin prompt, so this surface is
-- intentionally limited to non-interactive SSHFling commands.

on sshflingRun(argumentList, executableOverride)
    if executableOverride is missing value or executableOverride is "" then
        set executableName to system attribute "SSHFLING_EXECUTABLE"
        if executableName is "" then set executableName to "sshfling"
    else
        set executableName to executableOverride as text
    end if

    set commandParts to {quoted form of executableName}
    repeat with argumentValue in argumentList
        set end of commandParts to quoted form of (argumentValue as text)
    end repeat

    set previousDelimiters to AppleScript's text item delimiters
    try
        set AppleScript's text item delimiters to " "
        set commandLine to commandParts as text
    on error errorMessage number errorNumber
        set AppleScript's text item delimiters to previousDelimiters
        error errorMessage number errorNumber
    end try
    set AppleScript's text item delimiters to previousDelimiters

    try
        set outputText to do shell script "exec " & commandLine
        return {exitStatus:0, standardOutput:outputText, standardError:""}
    on error errorMessage number errorNumber
        if errorNumber is greater than or equal to 1 and errorNumber is less than or equal to 255 then
            return {exitStatus:errorNumber, standardOutput:"", standardError:errorMessage}
        end if
        error errorMessage number errorNumber
    end try
end sshflingRun

on run argumentList
    if (count of argumentList) is 1 and item 1 of argumentList is "--self-test" then
        set testExecutable to system attribute "SSHFLING_TEST_EXECUTABLE"
        if testExecutable is "" then
            set launchResult to my sshflingRun({"-c", "exit 23"}, "/bin/sh")
        else
            set launchResult to my sshflingRun({"--probe", "argument with spaces", "literal;$()&"}, testExecutable)
        end if
        if exitStatus of launchResult is 23 then return "ok"
        error "SSHFling AppleScript self-test returned the wrong status" number 1
    end if

    set launchResult to my sshflingRun(argumentList, missing value)
    if standardOutput of launchResult is not "" then log standardOutput of launchResult
    if exitStatus of launchResult is not 0 then
        set errorText to standardError of launchResult
        set errorStatus to exitStatus of launchResult
        error errorText number errorStatus
    end if
    return standardOutput of launchResult
end run
