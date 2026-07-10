FUNCTION SSHFlingVersion()
   RETURN SSHFLINGVERSION()

FUNCTION SSHFlingRun( aArguments )
   IF ! HB_ISARRAY( aArguments )
      RETURN 2
   ENDIF
   RETURN SSHFLINGRUN( aArguments )

PROCEDURE Main( ... )
   ErrorLevel( SSHFlingRun( hb_AParams() ) )
   RETURN
