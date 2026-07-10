require sshfling.fs

: versions-match? ( -- flag )
  sshfling-version 1 arg str= ;

: consumer-main ( -- status )
  versions-match? 0= if 1 exit then
  1 argv @ 2 cells + sshfling-run ;

consumer-main (bye)
