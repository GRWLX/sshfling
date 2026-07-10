; SPDX-License-Identifier: MIT
#include "SSHFling.au3"

If $CmdLine[0] = 1 And $CmdLine[1] = "--self-test" Then
    Local $aTestArguments[3] = ["/D", "/C", "exit 23"]
    Local $iTestStatus = _SSHFling_Run($aTestArguments, @ComSpec)
    Exit (($iTestStatus = 23) ? 0 : 1)
EndIf

If $CmdLine[0] = 0 Then Exit _SSHFling_Run()
Local $aArguments[$CmdLine[0]]
For $i = 1 To $CmdLine[0]
    $aArguments[$i - 1] = $CmdLine[$i]
Next
Exit _SSHFling_Run($aArguments)
