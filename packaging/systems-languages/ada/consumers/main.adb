with Ada.Command_Line;
with Ada.Strings.Unbounded;
with SSHFling;

procedure Main is
   use Ada.Strings.Unbounded;
   Arguments : SSHFling.Argument_List (1 .. 1);
   Expected : constant String := Ada.Command_Line.Argument (1);
   Status : Integer;
begin
   if SSHFling.Version /= Expected or else SSHFling.Runtime_Version /= Expected then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;
   Arguments (1) := To_Unbounded_String ("--version");
   Status := SSHFling.Run (Arguments);
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end Main;
