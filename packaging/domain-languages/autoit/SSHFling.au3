; SPDX-License-Identifier: MIT
; Unpublished launcher candidate. _SSHFling_Run starts a real child process
; and returns its exit code. Arguments are quoted for the Windows command line.

Func _SSHFling_Run($vArguments = Default, $sExecutable = "")
    If IsKeyword($vArguments) <> 1 And Not IsArray($vArguments) Then Return SetError(1, 0, 127)

    If $sExecutable = "" Then
        $sExecutable = EnvGet("SSHFLING_EXECUTABLE")
        If $sExecutable = "" Then $sExecutable = "sshfling.exe"
    EndIf
    If StringInStr($sExecutable, Chr(0), 1) Then Return SetError(2, 0, 127)

    Local $sCommand = _SSHFling_QuoteWindowsArgument($sExecutable)
    If IsArray($vArguments) Then
        For $i = 0 To UBound($vArguments) - 1
            If Not IsString($vArguments[$i]) Then Return SetError(3, $i, 127)
            If StringInStr($vArguments[$i], Chr(0), 1) Then Return SetError(4, $i, 127)
            $sCommand &= " " & _SSHFling_QuoteWindowsArgument($vArguments[$i])
        Next
    EndIf

    Local $iStatus = RunWait($sCommand, "", @SW_SHOW)
    If @error Then Return SetError(5, @error, 127)
    Return $iStatus
EndFunc

Func _SSHFling_QuoteWindowsArgument($sValue)
    Local $sQuote = Chr(34)
    Local $sSlash = Chr(92)
    Local $sResult = $sQuote
    Local $iSlashCount = 0

    For $i = 1 To StringLen($sValue)
        Local $sCharacter = StringMid($sValue, $i, 1)
        If $sCharacter = $sSlash Then
            $iSlashCount += 1
        ElseIf $sCharacter = $sQuote Then
            $sResult &= _SSHFling_Repeat($sSlash, $iSlashCount * 2 + 1) & $sQuote
            $iSlashCount = 0
        Else
            $sResult &= _SSHFling_Repeat($sSlash, $iSlashCount) & $sCharacter
            $iSlashCount = 0
        EndIf
    Next

    Return $sResult & _SSHFling_Repeat($sSlash, $iSlashCount * 2) & $sQuote
EndFunc

Func _SSHFling_Repeat($sValue, $iCount)
    Local $sResult = ""
    For $i = 1 To $iCount
        $sResult &= $sValue
    Next
    Return $sResult
EndFunc
