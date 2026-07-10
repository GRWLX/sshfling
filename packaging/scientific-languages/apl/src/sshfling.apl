∇Z←SSHFling∆PackageVersion
Z←'0.0.0'
∇

∇Z←SSHFling∆ConfiguredOr A;E;N;F
N←1⊃A
F←2⊃A
E←⎕ENV N
Z←F
→(0=1↑⍴E)/0
Z←⊃E[1;2]
∇

∇Z←SSHFling∆RuntimePath;Root
Root←SSHFling∆ConfiguredOr ('SSHFLING_PACKAGE_ROOT' '.')
Z←SSHFling∆ConfiguredOr ('SSHFLING_RUNTIME' (Root,'/runtime/sshfling.py'))
∇

∇Z←SSHFling∆TemplateDirectory;Root
Root←SSHFling∆ConfiguredOr ('SSHFLING_PACKAGE_ROOT' '.')
Z←SSHFling∆ConfiguredOr ('SSHFLING_TEMPLATE_DIR' (Root,'/runtime/templates'))
∇

∇Z←SSHFling∆ShellQuote S
Z←'''',S,''''
∇

∇Z←SSHFling∆NormalizeStatus S
Z←127
→(S<0)/0
Z←⌊S÷256
∇

∇Z←SSHFling∆Run Args;Runtime;Template;Python;Command;I;Arg;Handle;Wait
Z←127
Runtime←SSHFling∆RuntimePath
→(0≠('F' ⎕FIO[31] Runtime))/0
Template←SSHFling∆TemplateDirectory
Python←SSHFling∆ConfiguredOr ('SSHFLING_PYTHON' 'python3')
Command←'SSHFLING_TEMPLATE_DIR=',(SSHFling∆ShellQuote Template),' PYTHONUNBUFFERED=1 ',(SSHFling∆ShellQuote Python),' ',(SSHFling∆ShellQuote Runtime)
I←1
NextArg:→(I>⍴Args)/Execute
Arg←I⊃Args
→(0<+/''''=Arg)/0
Command←Command,' ',(SSHFling∆ShellQuote Arg)
I←I+1
→NextArg
Execute:Handle←'w' ⎕FIO[24] Command
→(Handle<0)/0
Wait←⎕FIO[25] Handle
Z←SSHFling∆NormalizeStatus Wait
∇

∇Z←SSHFling∆ApplicationArgs Args;I;N
Z←⍬
N←⍴Args
I←1
Next:→(I>N)/0
→('--'≡I⊃Args)/Found
I←I+1
→Next
Found:Z←I↓Args
∇

∇SSHFling∆WriteStatus Status;E;F;H;N
E←⎕ENV 'SSHFLING_APL_STATUS_FILE'
→(0=1↑⍴E)/0
F←⊃E[1;2]
H←'w' ⎕FIO[3] F
→(H<0)/0
N←(⍕Status) ⎕FIO[23] H
N←⎕FIO[4] H
∇
