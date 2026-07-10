: sshfling-bridge-path ( -- c-addr u )
  s" SSHFLING_FORTH_BRIDGE" getenv
  dup 0= if
    2drop s" /usr/local/lib/sshfling-forth/libsshfling_gforth.so"
  then ;

: open-sshfling-bridge ( -- handle )
  sshfling-bridge-path open-lib
  dup 0= if
    drop -1 throw
  then ;

open-sshfling-bridge constant sshfling-bridge-handle

: sshfling-symbol ( c-addr u -- address )
  sshfling-bridge-handle lib-sym
  dup 0= if
    drop -1 throw
  then ;

s" sshfling_gforth_version" sshfling-symbol constant sshfling-version-call
s" sshfling_gforth_run" sshfling-symbol constant sshfling-run-call

: sshfling-version ( -- c-addr u )
  sshfling-version-call call-c cstring>sstring ;

: sshfling-run ( argc argv -- status )
  sshfling-run-call call-c ;
