--  HAC: command-line build and execution tool for HAC (HAC Ada Compiler)
--  Usage, license etc. : see `Help` below and the HAC_Sys package (hac_sys.ads).
--  For a small version, see HAC_Mini (hac_mini.adb).
--

with HAC_Sys.Builder,
     HAC_Sys.Co_Defs,
     HAC_Sys.Librarian,
     HAC_Sys.PCode.Interpreter.In_Defs;

with HAL;

with Show_License;

with Ada.Calendar,
     Ada.Command_Line,
     Ada.Containers,
     Ada.Directories,
     Ada.Exceptions,
     Ada.Text_IO.Text_Streams;

procedure HAC is

  verbosity : Natural := 0;
  caveat       : constant String := "Caution: HAC is not a complete Ada compiler.";
  version_info : constant String :=
    "Compiler version: " & HAC_Sys.version & " dated " & HAC_Sys.reference & '.';

  HAC_margin_1 : constant String := "*******[ HAC ]*******   ";
  HAC_margin_2 : constant String := ". . . .[ HAC ]. . . .   ";
  HAC_margin_3 : constant String := "-------[ HAC ]-------   ";

  procedure PLCE (s : String) is
    use Ada.Text_IO;
  begin
    Put_Line (Current_Error, s);
  end PLCE;

  procedure NLCE is
    use Ada.Text_IO;
  begin
    New_Line (Current_Error);
  end NLCE;

  procedure Compilation_Feedback (message : String) is
  begin
    case verbosity is
      when 0      => null;
      when 1      => HAL.Put_Line (message);
      when others => HAL.Put_Line (HAC_margin_2 & message);
    end case;
  end Compilation_Feedback;

  function Search_File (simple_file_name, path : String) return String is
    sep_pos : Natural := path'First - 1;
    new_sep_pos : Natural;
  begin
    for i in path'Range loop
      new_sep_pos := sep_pos;
      if path (i) = ',' or path (i) = ';' then
        new_sep_pos := i;
      elsif i = path'Last then
        new_sep_pos := i + 1;
      end if;
      if new_sep_pos > sep_pos then
        declare
          full_file_name : constant String :=
            path (sep_pos + 1 .. new_sep_pos - 1) & HAL.Directory_Separator & simple_file_name;
        begin
          if HAL.Exists (full_file_name) then
            return full_file_name;
          end if;
        end;
      end if;
      sep_pos := new_sep_pos;
    end loop;
    return "";
  end Search_File;

  command_line_source_path : HAL.VString;

  asm_dump_file_name : HAL.VString;
  cmp_dump_file_name : HAL.VString;

  procedure Compile_and_interpret_file (Ada_file_name : String; arg_pos : Positive) is
    use HAC_Sys.PCode.Interpreter;
    use Ada.Calendar, Ada.Command_Line, Ada.Containers, Ada.Text_IO;

    function Search_Source_File (simple_file_name : String) return String is
      --  Search order: same as GNAT's,
      --  cf. 4.2.2 Search Paths and the Run-Time Library (RTL).
    begin
      --  1) The directory containing the source file of the main unit
      --     being compiled (the file name on the command line).
      declare
        fn : constant String :=
          Ada.Directories.Containing_Directory (Ada_file_name) &
          HAL.Directory_Separator &
          simple_file_name;
      begin
        if HAL.Exists (fn) then
          return fn;
        end if;
      end;
      --  2) Each directory named by an -I switch given on the
      --     hac command line, in the order given.
      declare
        fn : constant String :=
          Search_File (simple_file_name, HAL.To_String (command_line_source_path));
      begin
        if fn /= "" then
          return fn;
        end if;
      end;
      --  3) Omitted.
      --  4) Each of the directories listed in the value of the ADA_INCLUDE_PATH environment variable.
      declare
        fn : constant String :=
          Search_File (simple_file_name, HAL.To_String (HAL.Get_Env ("ADA_INCLUDE_PATH")));
      begin
        if fn /= "" then
          return fn;
        end if;
      end;
      return "";
    end Search_Source_File;

    function Exists_Source (simple_file_name : String) return Boolean is
    begin
      return Search_Source_File (simple_file_name) /= "";
    end Exists_Source;

    procedure Open_Source (simple_file_name : String; stream : out HAC_Sys.Co_Defs.Source_Stream_Access) is
      full_file_name : constant String := Search_Source_File (simple_file_name);
    begin
      HAC_Sys.Librarian.default_open_file (full_file_name, stream);
    end Open_Source;

    procedure Close_Source (simple_file_name : String) is
      full_file_name : constant String := Search_Source_File (simple_file_name);
    begin
      HAC_Sys.Librarian.default_close_file (full_file_name);
    end Close_Source;

    procedure Show_Line_Information (
      File_Name   : String;   --  Example: hac-pcode-interpreter.adb
      Block_Name  : String;   --  Example: HAC.PCode.Interpreter.Do_Write_Formatted
      Line_Number : Positive
    )
    is
    begin
      PLCE
        (File_Name & ": " &
         Block_Name & " at line" &
         Integer'Image (Line_Number));
    end Show_Line_Information;
    --
    procedure CIO_Trace_Back is new Show_Trace_Back (Show_Line_Information);
    --
    procedure Failure is
      use HAL;
    begin
      if Ends_With (+Ada_file_name, ".hac") then
        --  Main has the "HAC script extension", possibly run
        --  from Explorer, Nautilus, etc.
        HAL.Put ("Failure in " & Ada_file_name & ", press Return");
        HAL.Skip_Line;
      end if;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
    end Failure;
    --
    f : Ada.Text_IO.File_Type;
    t1, t2 : Ada.Calendar.Time;
    BD : HAC_Sys.Builder.Build_Data;
    post_mortem : Post_Mortem_Data;
    unhandled_found : Boolean;
    shebang_offset : Natural;
    trace : constant HAC_Sys.Co_Defs.Compilation_Trace_Parameters :=
      (pipe         => null,
       progress     => HAC_Sys.Builder.Unrestricted (Compilation_Feedback'Address),
       detail_level => verbosity);

  begin
    if verbosity > 1 then
      New_Line;
      Put_Line (HAC_margin_1 & version_info);
      Put_Line (HAC_margin_1 & caveat & " Type ""hac"" for license.");
    end if;
    Open (f, In_File, Ada_file_name);
    HAC_Sys.Builder.Skip_Shebang (f, shebang_offset);
    BD.Set_Diagnostic_File_Names (HAL.To_String (asm_dump_file_name), HAL.To_String (cmp_dump_file_name));
    BD.Set_Main_Source_Stream (Text_Streams.Stream (f), Ada_file_name, shebang_offset);
    BD.Set_Message_Feedbacks (trace);
    BD.LD.Set_Source_Access
      (Exists_Source'Unrestricted_Access,
       Open_Source'Unrestricted_Access,
       Close_Source'Unrestricted_Access);
    t1 := Clock;
    BD.Build_Main;
    t2 := Clock;
    Close (f);
    if verbosity >= 2 then
      Put_Line (
        HAC_margin_2 & "Build finished in" &
        Duration'Image (t2 - t1) &
        " seconds." &
        Integer'Image (BD.Total_Compiled_Lines) & " lines compiled."
      );
    end if;
    --
    if not BD.Build_Successful then
      PLCE ("Errors found, build failed.");
      Failure;
      return;
    end if;
    if verbosity >= 2 then
      Put_Line (HAC_margin_2 & "Object code size:" &
                Natural'Image (BD.Object_Code_Size) &
                " of" &
                Natural'Image (HAC_Sys.Builder.Maximum_Object_Code_Size) &
                " Virtual Machine instructions.");
      if BD.Folded_Instructions + BD.Specialized_Instructions > 0 then
        Put_Line (HAC_margin_2 & "Code optimization:");
        Put_Line (HAC_margin_2 & "  " & Natural'Image (BD.Folded_Instructions) &
          " instructions folded");
        Put_Line (HAC_margin_2 & "  " & Natural'Image (BD.Specialized_Instructions) &
          " instructions specialized");
      end if;
      Put_Line (HAC_margin_2 & "Starting p-code VM interpreter...");
    end if;
    t1 := Clock;
    Interpret_on_Current_IO (
      BD,
      arg_pos,
      Ada.Directories.Full_Name (Ada_file_name),
      post_mortem
    );
    t2 := Clock;
    unhandled_found := Is_Exception_Raised (post_mortem.Unhandled);
    if verbosity >= 2 then
      if unhandled_found then
        Put_Line (
          HAC_margin_3 & "VM interpreter stopped execution of " &
            Ada_file_name & " due to an unhandled exception.");
      else
        Put_Line (
          HAC_margin_3 & "VM interpreter done after" &
          Duration'Image (t2 - t1) & " seconds."
        );
      end if;
    end if;
    if unhandled_found then
      PLCE ("HAC VM: raised " & Image (post_mortem.Unhandled));
      PLCE (Message (post_mortem.Unhandled));
      PLCE ("Trace-back: approximate location");
      CIO_Trace_Back (post_mortem.Unhandled);
      Failure;
    elsif verbosity >= 1 then
      Put_Line ("Execution of " & Ada_file_name & " completed.");
    end if;
    if verbosity >= 2 then
      Put_Line (
        "Maximum stack usage:" &
        Integer'Image (post_mortem.Max_Stack_Usage) & " of" &
        Integer'Image (post_mortem.Stack_Size) & " memory units, around" &
        Integer'Image (100 * post_mortem.Max_Stack_Usage / post_mortem.Stack_Size) & "%."
      );
    end if;
    if verbosity >= 1 then
      if post_mortem.Open_Files.Length > 0 then
        Put_Line ("List of files that were left open during execution:");
        for ofd of post_mortem.Open_Files loop
          Put_Line
           ("  Name: " & HAL.To_String (ofd.Name) &
            ", mode: " & File_Mode'Image (ofd.Mode));
        end loop;
      end if;
    end if;
  exception
    when E : Abnormal_Termination =>
      PLCE (Ada.Exceptions.Exception_Message (E));
      Failure;
    when Name_Error =>
      PLCE
        (HAC_margin_3 &
         "Error: file """ & Ada_file_name &
         """ not found (perhaps in exm or test subdirectory ?)");
      Failure;
  end Compile_and_interpret_file;

  assembler_output_name : constant String := "asm_dump.pca";       --  PCA = PCode Assembler
  compiler_dump_name    : constant String := "compiler_dump.lst";

  procedure Help (level : Positive) is
    use Ada.Text_IO;
  begin
    PLCE ("HAC: command-line build and execution tool for HAC (HAC Ada Compiler)");
    PLCE (version_info);
    PLCE ("URL: " & HAC_Sys.web);
    NLCE;
    PLCE ("Usage: hac [options] main.adb [command-line parameters for main]");
    NLCE;
    PLCE ("Options: -h     : this help");
    PLCE ("         -I     : specify source files search path");
    PLCE ("         -v, v1 : verbose");
    PLCE ("         -v2    : very verbose");
    PLCE ("         -a     : assembler output in " & assembler_output_name);
    PLCE ("         -d     : dump compiler information in " & compiler_dump_name);
    PLCE ("         -h2    : show more help about options");
    NLCE;
    PLCE (caveat);
    PLCE ("Note: HAC (this command-line tool) accepts source files with shebang's,");
    PLCE ("      for instance:   #!/usr/bin/env hac     or     #!/usr/bin/hac");
    Show_License (Current_Error, "hac_sys.ads");
    if level > 1 then
      PLCE ("Extended help for HAC");
      PLCE ("---------------------");
      NLCE;
      PLCE ("Option -I : specify source files search path");
      NLCE;
      PLCE ("  The search path is a list of directories separated by commas (,) or semicolons (;).");
      PLCE ("  HAC searches Ada source files in the following order:");
      PLCE ("    1) The directory containing the source file of the main unit");
      PLCE ("         being compiled (the file name on the command line).");
      PLCE ("    2) Each directory named by an -I switch given on the");
      PLCE ("         hac command line, in the order given.");
      PLCE ("    3) Each of the directories listed in the value of the ADA_INCLUDE_PATH");
      PLCE ("         environment variable.");
    end if;
  end Help;

  hac_ing    : Boolean  := False;
  quit       : Boolean  := False;
  help_level : Positive := 1;

  procedure Process_Argument (arg : String; arg_pos : Positive) is
    opt : constant String := arg (arg'First + 1 .. arg'Last);
    use HAL;
  begin
    if arg (arg'First) = '-' then
      if opt'Length = 0 then
        PLCE ("Missing option code: ""-""");
        NLCE;
        quit := True;
        return;
      end if;
      case opt (opt'First) is
        when 'a' =>
          asm_dump_file_name := HAL.To_VString (assembler_output_name);
        when 'd' =>
          cmp_dump_file_name := HAL.To_VString (compiler_dump_name);
        when 'h' =>
          if opt'Length > 1 and then opt (opt'First + 1) = '2' then
            help_level := 2;
          end if;
          quit := True;
        when 'I' =>
          if command_line_source_path /= "" then
            command_line_source_path := command_line_source_path & ';';
          end if;
          command_line_source_path :=
            command_line_source_path & HAL.To_VString (opt (opt'First + 1 .. opt'Last));
        when 'v' =>
          verbosity := 1;
          if opt'Length > 1 and then opt (opt'First + 1) = '2' then
            verbosity := 2;
          end if;
        when others =>
          PLCE ("Unknown option: """ & arg & '"');
          NLCE;
          quit := True;
      end case;
    else
      Compile_and_interpret_file (arg, arg_pos);
      hac_ing := True;
      quit := True;  --  The other arguments are for the HAC program.
    end if;
  end Process_Argument;

  use Ada.Command_Line;

begin
  for i in 1 .. Argument_Count loop
    Process_Argument (Argument (i), i);
    exit when quit;
  end loop;
  if not hac_ing then
    Help (help_level);
    if verbosity > 1 then
      Ada.Text_IO.Put_Line ("Size of a HAC VM memory unit:" &
        Integer'Image (HAC_Sys.PCode.Interpreter.In_Defs.Data_Type'Size / 8) &
        " bytes"
      );
    end if;
  end if;
end HAC;
