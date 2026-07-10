with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings; use Interfaces.C.Strings;
with System;

package body SSHFling is
   function Launcher_Version return chars_ptr
      with Import, Convention => C, External_Name => "sshfling_launcher_version";

   function Launcher_Run
     (Count : size_t; Arguments : System.Address) return int
      with Import, Convention => C, External_Name => "sshfling_launcher_run";

   function Runtime_Version return String is
   begin
      return Value (Launcher_Version);
   end Runtime_Version;

   function Run (Arguments : Argument_List) return Integer is
      Pointers : aliased chars_ptr_array (1 .. size_t (Arguments'Length));
      Status : int;
   begin
      if Arguments'Length = 0 then
         return Integer (Launcher_Run (0, System.Null_Address));
      end if;

      for Index in Arguments'Range loop
         Pointers (size_t (Index - Arguments'First) + 1) :=
           New_String (To_String (Arguments (Index)));
      end loop;
      Status := Launcher_Run (size_t (Arguments'Length), Pointers'Address);
      for Pointer of Pointers loop
         Free (Pointer);
      end loop;
      return Integer (Status);
   end Run;
end SSHFling;
