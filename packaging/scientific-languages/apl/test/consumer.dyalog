:Trap 0
    ⎕FIX 'file://src/SSHFling.dyalog'
:Else
    ⎕OFF 1
:EndTrap

:Namespace SSHFlingConsumer
    ∇ status←Run smoke
      status←SSHFling.Run⊂'--version'
      :If 0=status
          status←SSHFling.Run 'init' smoke '--force' '--session-seconds' '60'
      :EndIf
    ∇
:EndNamespace

smoke←System.Environment.GetEnvironmentVariable 'SSHFLING_SMOKE_PROJECT'
⎕OFF SSHFlingConsumer.Run smoke
