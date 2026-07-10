       IDENTIFICATION DIVISION.
       PROGRAM-ID. SSHFling.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-STATUS PIC S9(9) COMP-5 VALUE 0.

       PROCEDURE DIVISION.
           CALL "sshfling_launcher_run_process_arguments"
               RETURNING WS-STATUS
           END-CALL
           MOVE WS-STATUS TO RETURN-CODE
           GOBACK.
       END PROGRAM SSHFling.
