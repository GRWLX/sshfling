require sshfling.fs

: sshfling-cli ( -- status )
  argc @ 1- argv @ cell+ sshfling-run ;

sshfling-cli (bye)
