with HAC.Parser.Helpers;                use HAC.Parser.Helpers;
with HAC.PCode;                         use HAC.PCode;
with HAC.Scanner;
with HAC.UErrors;                       use HAC.UErrors;

package body HAC.Parser.Tasking is

  use HAC.Compiler, HAC.Data;

  ------------------------------------------------------------------
  -------------------------------------------------Task_Declaration-
  --  Hathorn
  procedure Task_Declaration (
    CD      : in out HAC.Compiler.Compiler_Data;
    FSys    :        HAC.Data.Symset;
    Level_A :        Integer
  )
  is
    Level : Integer := Level_A;
    I, T0         : Integer;
    TaskID        : Alfa;
    saveLineCount : constant Integer := CD.Line_Count;  --  Source line where Task appeared
    procedure InSymbol is begin Scanner.InSymbol (CD); end;
  begin
    InSymbol;
    if CD.Sy = BODY_Symbol then  --  Task Body
      InSymbol;
      I      := Locate_Identifier (CD, CD.Id, Level);
      TaskID := CD.IdTab (I).Name;
      CD.Blocks_Table (CD.IdTab (I).Block_Ref).SrcFrom := saveLineCount;  --  (* Manuel *)
      InSymbol;
      Block (CD, FSys, False, False, Level + 1, I, TaskID, TaskID);  --  !! up/low case
      Emit1 (CD, k_Exit_Call, CallSTDP);
    else                         --  Task Specification
      if CD.Sy = IDent then
        TaskID := CD.Id;
      else
        Error (CD, err_identifier_missing);
        CD.Id := Empty_Alfa;
      end if;
      CD.Tasks_Definitions_Count := CD.Tasks_Definitions_Count + 1;
      if CD.Tasks_Definitions_Count > TaskMax then
        Fatal (TASKS);  --  Exception is raised there.
      end if;
      Enter (CD, Level, TaskID, TaskID, aTask);  --  !! casing
      CD.Tasks_Definitions_Table (CD.Tasks_Definitions_Count) := CD.Id_Count;
      Enter_Block (CD, CD.Id_Count);
      CD.IdTab (CD.Id_Count).Block_Ref := CD.Blocks_Count;
      InSymbol;
      if CD.Sy = Semicolon then
        InSymbol;  --  Task with no entries
      else  --  Parsing the Entry specs
        Need (CD, IS_Symbol, err_IS_missing);
        if Level = Nesting_Level_Max then
          Fatal (LEVELS);  --  Exception is raised there.
        end if;
        Level              := Level + 1;
        CD.Display (Level) := CD.Blocks_Count;
        while CD.Sy = ENTRY_Symbol loop
          InSymbol;
          if CD.Sy /= IDent then
            Error (CD, err_identifier_missing);
            CD.Id := Empty_Alfa;
          end if;
          CD.Entries_Count := CD.Entries_Count + 1;
          if CD.Entries_Count > EntryMax then
            Fatal (ENTRIES);  --  Exception is raised there.
          end if;
          Enter (CD, Level, CD.Id, CD.Id_with_case, aEntry);
          CD.Entries_Table (CD.Entries_Count) := CD.Id_Count;  --  point to identifier table location
          T0                                  := CD.Id_Count;  --  of TaskID
          InSymbol;
          Block (CD, FSys, False, False, Level + 1, CD.Id_Count,
                 CD.IdTab (CD.Id_Count).Name, CD.IdTab (CD.Id_Count).Name_with_case);
          CD.IdTab (T0).Adr_or_Sz := CD.Tasks_Definitions_Count;
          if CD.Sy = Semicolon then
            InSymbol;
          else
            Error (CD, err_semicolon_missing);
          end if;
        end loop;  --  while CD.Sy = ENTRY_Symbol

        Level := Level - 1;
        Test_END_Symbol (CD);
        if CD.Sy = IDent and CD.Id = TaskID then
          InSymbol;
        else
          Skip (CD, Semicolon, err_incorrect_block_name);
        end if;
        Test_Semicolon (CD, FSys);
      end if;
    end if;
  end Task_Declaration;

end HAC.Parser.Tasking;
