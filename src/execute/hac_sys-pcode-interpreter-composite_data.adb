package body HAC_Sys.PCode.Interpreter.Composite_Data is

  procedure Do_Composite_Data_Operation (CD : Compiler_Data; ND : in out Interpreter_Data) is
    Curr_TCB : Task_Control_Block renames ND.TCB (ND.CurTask);
    IR : Order renames ND.IR;
    use Defs;
    use type HAC_Integer;

    procedure Do_Array_Index (Element_Size : Index) is
      ATI : constant Integer := Integer (IR.Y);
      ATE : ATabEntry renames CD.Arrays_Table (ATI);
      Idx : constant Index := Index (ND.S (Curr_TCB.T).I);
    begin
      if Idx < ATE.Low then
        raise VM_Out_of_Range with ": index below array's lower bound";
      elsif Idx > ATE.High then
        raise VM_Out_of_Range with ": index above array's upper bound";
      end if;
      Pop (ND);  --  Pull array index, then adjust array element pointer.
      ND.S (Curr_TCB.T).I := ND.S (Curr_TCB.T).I + HAC_Integer ((Idx - ATE.Low) * Element_Size);
    end Do_Array_Index;

    procedure Do_Load_Block is
      H1, H2 : Index;
    begin
      H1 := Index (ND.S (Curr_TCB.T).I);  --  Pull source address
      Pop (ND);
      H2 := Index (IR.Y) + Curr_TCB.T;    --  Stack top after pushing block
      if H2 > Curr_TCB.STACKSIZE then
        raise VM_Stack_Overflow;
      end if;
      while Curr_TCB.T < H2 loop
        Curr_TCB.T := Curr_TCB.T + 1;
        ND.S (Curr_TCB.T) := ND.S (H1);
        H1 := H1 + 1;
      end loop;
    end Do_Load_Block;

    procedure Do_Copy_Block is
      --  [T-1].all (0 .. IR.Y - 1) := [T].all (0 .. IR.Y - 1)
      Dst_Addr, Src_Addr, Last : Index;
    begin
      Dst_Addr := Index (ND.S (Curr_TCB.T - 1).I);
      Src_Addr := Index (ND.S (Curr_TCB.T).I);
      Last := Index (IR.Y) - 1;
      ND.S (Dst_Addr .. Dst_Addr + Last) := ND.S (Src_Addr .. Src_Addr + Last);
      Pop (ND, 2);
    end Do_Copy_Block;

    procedure Do_String_Literal_Assignment is
      H1, H2, H3, H4, H5 : Index;
    begin
      H1 := Index (ND.S (Curr_TCB.T - 2).I);  --  Address of array
      H2 := Index (ND.S (Curr_TCB.T).I);      --  Index to string table
      H3 := Index (IR.Y);                     --  Size of array
      H4 := Index (ND.S (Curr_TCB.T - 1).I);  --  Length of string
      if H3 < H4 then
        H5 := H1 + H3;    --  H5 is H1 + min of H3, H4
      else
        H5 := H1 + H4;
      end if;
      while H1 < H5 loop
        --  Copy H5-H1 characters to the stack
        ND.S (H1).I := Character'Pos (CD.Strings_Constants_Table (H2));
        H1 := H1 + 1;
        H2 := H2 + 1;
      end loop;
      --  Padding (does not happen, since lengths are checked at compile-time)
      H5 := Index (ND.S (Curr_TCB.T - 2).I) + H3;  --  H5 = H1 + H3
      while H1 < H5 loop
        --  Fill with blanks if req'd
        ND.S (H1).I := Character'Pos (' ');
        H1 := H1 + 1;
      end loop;
      Pop (ND, 3);
    end Do_String_Literal_Assignment;

  begin
    case Composite_Data_Opcode (ND.IR.F) is
      when k_Array_Index_Element_Size_1 => Do_Array_Index (1);
      when k_Array_Index                => Do_Array_Index (CD.Arrays_Table (Integer (IR.Y)).Element_Size);
      when k_Record_Field_Offset        => ND.S (Curr_TCB.T).I := ND.S (Curr_TCB.T).I + IR.Y;
      when k_Load_Block                 => Do_Load_Block;
      when k_Copy_Block                 => Do_Copy_Block;
      when k_String_Literal_Assignment  => Do_String_Literal_Assignment;
    end case;
  end Do_Composite_Data_Operation;

end HAC_Sys.PCode.Interpreter.Composite_Data;
