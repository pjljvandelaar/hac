-------------------------------------------------------------------------------------
--
--  HAC - HAC Ada Compiler
--
--  A compiler in Ada for an Ada subset
--
--  Copyright, license, etc. : see top package.
--
-------------------------------------------------------------------------------------
--

with HAC_Sys.Co_Defs, HAC_Sys.Defs, HAC_Sys.Li_Defs;

with Ada.Streams, Ada.Text_IO;

package HAC_Sys.Compiler is

  use HAC_Sys.Co_Defs, HAC_Sys.Defs;

  --  Main compilation procedure.
  --
  procedure Compile_Main (
    CD                 : in out Co_Defs.Compiler_Data;
    LD                 : in out Li_Defs.Library_Data;
    main_name_hint     :        String;  --  This is used for circular unit dependency detection
    asm_dump_file_name :        String  := "";  --  Assembler output of compiled object code
    cmp_dump_file_name :        String  := "";  --  Compiler dump
    listing_file_name  :        String  := "";  --  Listing of source code with details
    var_map_file_name  :        String  := ""   --  Output of variables (map)
  );

  --  Compile unit not yet in the library.
  --  Registration into the library is done after, by the librarian.
  --
  procedure Compile_Unit (
    CD                 : in out Co_Defs.Compiler_Data;
    LD                 : in out Li_Defs.Library_Data;
    upper_name         :        String;
    file_name          :        String;
    as_specification   :        Boolean;
    kind               :    out Li_Defs.Unit_Kind  --  The unit kind is discovered by parsing.
  );

  --  Set current source stream (file, editor data, zipped file,...)
  procedure Set_Source_Stream (
    SD         : in out Co_Defs.Current_Unit_Data;
    s          : access Ada.Streams.Root_Stream_Type'Class;
    file_name  : in     String;       --  Can be a virtual name (editor title, zip entry)
    start_line : in     Natural := 0  --  We could have a shebang or other Ada sources before
  );

  function Get_Current_Source_Name (SD : Co_Defs.Current_Unit_Data) return String;

  --  Skip an eventual "shebang", e.g.: #!/usr/bin/env hac
  --  The Ada source begins from next line.
  --
  procedure Skip_Shebang (f : in out Ada.Text_IO.File_Type; shebang_offset : out Natural);

  procedure Set_Error_Pipe (
    CD   : in out Compiler_Data;
    pipe :        Smart_error_pipe
  );

  function Unit_Compilation_Successful (CD : Compiler_Data) return Boolean;
  function Unit_Object_Code_Size (CD : Compiler_Data) return Natural;

end HAC_Sys.Compiler;
