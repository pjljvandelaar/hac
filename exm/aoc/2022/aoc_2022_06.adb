--  Solution to Advent of Code 2022, Day 6
------------------------------------------
--  Tuning Trouble
--
--  https://adventofcode.com/2022/day/6
--  Copy of questions in: aoc_2022_06_questions.txt

--  For building this program with "full Ada",
--  files hat*.ad* are in ../../../src
with HAT;

procedure AoC_2022_06 is
  use HAT;

  T0 : constant Time := Clock;
  r : array (1 .. 2) of Integer;

  f : File_Type;
  s : VString;
  c : Character;
  cc : array (Character) of Natural;
  marker_length : Positive;
  ok : Boolean;
begin
  Open (f, "aoc_2022_06.txt");
  Get_Line (f, s);
  Close (f);
  for part in 1 .. 2 loop
    for c in Character loop
      cc (c) := 0;
    end loop;
    for i in 1 .. Length (s) loop
      c := Element (s, i);
      cc (c) := cc (c) + 1;
      case part is
        when 1 => marker_length := 4;
        when 2 => marker_length := 14;
      end case;
      if i >= marker_length then
        if i > marker_length then
          --  Forget older occurrences.
          c := Element (s, i - marker_length);
          cc (c) := cc (c) - 1;
        end if;
        ok := True;
        for c in Character loop
          ok := ok and cc (c) < 2;
        end loop;
        if ok then
          r (part) := i;
          exit;
        end if;
      end if;
    end loop;
  end loop;
  if Argument_Count >= 2 then
    --  Compiler test mode.
    if r (1) /= Integer'Value (To_String (Argument (1))) or
       r (2) /= Integer'Value (To_String (Argument (2)))
    then
      Set_Exit_Status (1);  --  Compiler test failed.
    end if;
  else
    Put_Line (+"Done in: " & (Clock - T0) & " seconds");
    Put_Line (+"Number of characters that need to be " &
               " processed before the first...");
    Put_Line (+"  (part 1) start-of-packet marker . . . : " & Image (r (1)));
    Put_Line (+"  (part 2) start-of-message marker  . . : " & Image (r (2)));
    --  Part 1: validated by AoC: 1802
    --  Part 2: validated by AoC: 3551
  end if;
end AoC_2022_06;
