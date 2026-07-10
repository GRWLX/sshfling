with Ada.Command_Line;
with Ada.Strings.Unbounded;
with SSHFling;

procedure SSHFling_Main is
   use Ada.Strings.Unbounded;
   Count : constant Natural := Ada.Command_Line.Argument_Count;
   Arguments : SSHFling.Argument_List (1 .. Count);
   Status : Integer;
begin
   for Index in Arguments'Range loop
      Arguments (Index) := To_Unbounded_String (Ada.Command_Line.Argument (Index));
   end loop;
   Status := SSHFling.Run (Arguments);
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end SSHFling_Main;
