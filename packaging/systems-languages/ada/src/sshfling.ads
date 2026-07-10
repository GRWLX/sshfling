with Ada.Strings.Unbounded;

package SSHFling is
   Version : constant String := "0.0.0";

   subtype Argument is Ada.Strings.Unbounded.Unbounded_String;
   type Argument_List is array (Natural range <>) of Argument;

   function Runtime_Version return String;
   function Run (Arguments : Argument_List) return Integer;
end SSHFling;
