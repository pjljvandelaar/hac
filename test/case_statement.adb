with HAC_Pack; use HAC_Pack;

procedure Case_Statement is

  after_int_case : Boolean := False;

  procedure Test_Int (i : Integer) is
  begin
    case (2*(i + 1)) / 2 - 1 is
      when 1 | -1 =>
        if abs (i) /= 1 then
          Put_Line ("Compiler bug [Int, A]");
        end if;
      when -7 =>
        if i + 7 /= 0 then
          Put_Line ("Compiler bug [Int, B]");
        end if;
      when others => null;
      --  !! When "OTHERS" omitted: HAC compiles but the VM enters a Case_Check_Error state.
      when 2 => null;
    end case;
    after_int_case := True;
  end Test_Int;

  procedure Test_Char (c: Character) is
  begin
    case c is
      when 'a' | 'A' =>
        if (c /= 'a') or (c /= 'A') then
          Put(c); Put_Line ("  Compiler bug [Char, A]");
        end if;
      when others => null;
    end case;
  end Test_Char;

begin
  for i in -10 .. 10 loop
    Test_Int (i);
  end loop;
  if not after_int_case then
    Put_Line ("Compiler bug [Int, Z]");
  end if;
  --
  for c in 'A' .. 'z' loop
    Test_Char (c);
  end loop;
end Case_Statement;