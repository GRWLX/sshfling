FUNCTION SSHFlingVersion()
   RETURN SSHFLINGNATIVEVERSION()

FUNCTION SSHFlingRun( aArguments )
   IF ! HB_ISARRAY( aArguments )
      RETURN 2
   ENDIF
   RETURN SSHFLINGNATIVERUN( aArguments )

PROCEDURE Main( ... )
   ErrorLevel( SSHFlingRun( hb_AParams() ) )
   RETURN
