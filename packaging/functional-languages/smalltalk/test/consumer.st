| smoke |
smoke := Smalltalk arguments first.
(SSHFling run: #('--version')) = 0 ifFalse: [ObjectMemory quit: 1].
(SSHFling run: {'init'. smoke. '--force'. '--session-seconds'. '60'}) = 0
    ifFalse: [ObjectMemory quit: 1].
(File exists: smoke, Directory pathSeparator asString, 'production',
    Directory pathSeparator asString, 'sshfling-session')
    ifFalse: [ObjectMemory quit: 1].
ObjectMemory quit: 0.
