' SPDX-License-Identifier: MIT
Option Explicit

' Unpublished launcher candidate. WScript.Shell.Run starts the real process,
' waits, and returns its status. It does not provide an interactive stream API.

Function RepeatText(ByVal value, ByVal count)
    Dim result, index
    result = ""
    For index = 1 To count
        result = result & value
    Next
    RepeatText = result
End Function

Function QuoteWindowsArgument(ByVal value)
    Dim quote, slash, result, slashCount, index, character
    quote = Chr(34)
    slash = Chr(92)
    result = quote
    slashCount = 0

    For index = 1 To Len(value)
        character = Mid(value, index, 1)
        If character = slash Then
            slashCount = slashCount + 1
        ElseIf character = quote Then
            result = result & RepeatText(slash, slashCount * 2 + 1) & quote
            slashCount = 0
        Else
            result = result & RepeatText(slash, slashCount) & character
            slashCount = 0
        End If
    Next
    QuoteWindowsArgument = result & RepeatText(slash, slashCount * 2) & quote
End Function

Function RunSSHFling(ByVal arguments, ByVal executableOverride)
    Dim shell, executable, commandLine, index, upperBound, status, launchError
    Set shell = CreateObject("WScript.Shell")
    executable = executableOverride
    If Len(executable) = 0 Then
        executable = shell.ExpandEnvironmentStrings("%SSHFLING_EXECUTABLE%")
        If executable = "%SSHFLING_EXECUTABLE%" Or Len(executable) = 0 Then
            executable = "sshfling.exe"
        End If
    End If

    commandLine = QuoteWindowsArgument(CStr(executable))
    On Error Resume Next
    upperBound = UBound(arguments)
    If Err.Number <> 0 Then
        upperBound = -1
        Err.Clear
    End If
    On Error GoTo 0
    For index = 0 To upperBound
        commandLine = commandLine & " " & QuoteWindowsArgument(CStr(arguments(index)))
    Next

    On Error Resume Next
    status = shell.Run(commandLine, 1, True)
    launchError = Err.Number
    Err.Clear
    On Error GoTo 0
    If launchError <> 0 Then
        WScript.Echo "Could not start SSHFling (VBScript error " & launchError & ")."
        RunSSHFling = 127
    Else
        RunSSHFling = status
    End If
End Function

Dim cliArguments, argumentCount, argumentIndex, exitStatus, shellForTest
argumentCount = WScript.Arguments.Count

If argumentCount = 1 And WScript.Arguments(0) = "--self-test" Then
    Set shellForTest = CreateObject("WScript.Shell")
    exitStatus = RunSSHFling( _
        Array("/D", "/C", "exit 23"), _
        shellForTest.ExpandEnvironmentStrings("%ComSpec%"))
    If exitStatus = 23 Then WScript.Quit 0
    WScript.Quit 1
End If

If argumentCount = 0 Then
    cliArguments = Array()
Else
    ReDim cliArguments(argumentCount - 1)
    For argumentIndex = 0 To argumentCount - 1
        cliArguments(argumentIndex) = WScript.Arguments(argumentIndex)
    Next
End If

exitStatus = RunSSHFling(cliArguments, "")
WScript.Quit exitStatus
