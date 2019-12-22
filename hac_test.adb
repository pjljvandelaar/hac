with HAC.Data, HAC.Compiler, HAC.PCode.Interpreter;

with Ada.Calendar;                      use Ada.Calendar;
with Ada.Command_Line;                  use Ada.Command_Line;
with Ada.Streams.Stream_IO;             use Ada.Streams.Stream_IO;
with Ada.Text_IO;                       use Ada.Text_IO;

with GNAT.Traceback.Symbolic, Ada.Exceptions;

procedure HAC_Test is

  procedure Compile_and_interpret_file(name: String) is
    f : Ada.Streams.Stream_IO.File_Type;
    t1, t2 : Time;
  begin
    New_Line;
    Put_Line ("*******[HAC]*******   Compiling from file: " & name);
    Open (f, In_File, name);
    HAC.Data.Line_Count:= 0;
    HAC.Data.c_Set_Stream (HAC.Data.Stream_Access(Stream(f)), name);
    t1 := Clock;
    HAC.Compiler.Compile;
    t2 := Clock;
    Close (f);
    Put_Line (
      "*******[HAC]*******   Compilation finished in " &
      (Duration'Image(t2-t1)) &
      " seconds."
    );
    --
    if HAC.Data.Err_Count = 0 then
      HAC.PCode.Interpreter.Interpret_on_Current_IO;
    end if;
  exception
    when Ada.Streams.Stream_IO.Name_Error =>
      Put_Line("Error: file not found (perhaps in hac_exm subdirectory ?)");
  end Compile_and_interpret_file;

begin
  if Argument_Count = 0 then
    Compile_and_interpret_file("test.adb");
  else
    for i in 1..Argument_Count loop
      Compile_and_interpret_file(Argument(i));
    end loop;
  end if;
exception
  when E: others =>
    New_Line(Standard_Error);
    Put_Line(Standard_Error,
             "--------------------[ Unhandled exception ]-----------------");
    Put_Line(Standard_Error, " > Name of exception . . . . .: " &
             Ada.Exceptions.Exception_Name(E) );
    Put_Line(Standard_Error, " > Message for exception . . .: " &
             Ada.Exceptions.Exception_Message(E) );
    Put_Line(Standard_Error, " > Trace-back of call stack: " );
    Put_Line(Standard_Error, GNAT.Traceback.Symbolic.Symbolic_Traceback(E) );
end HAC_Test;
