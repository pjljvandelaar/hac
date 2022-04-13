--  Testing library-level packages.
--  We create the packages for Pkg_Demo.

with HAL;

procedure Pkg_Demo_Gen is

  --  This type controls the location of WITH's in
  --  packages further in the dependency tree.
  --
  type Test_Mode is (all_in_spec, mixed, all_in_bodies);

  use HAL;

  max_depth : constant := 2;
  children  : constant := 3;

  procedure Generate (prefix : VString; depth : Natural; mode : Test_Mode) is
    f : File_Type;
    name : constant VString := "X_Pkg_Demo_" & prefix;
    file_name : constant VString := To_Lower (name);
    subtype Child_Range is Integer range 1 .. children;
    with_in_spec : array (Child_Range) of Boolean;
  begin
    if Argument_Count > 0 and then Argument (1) = "delete" then
      Delete_File (file_name & ".adb");
      Delete_File (file_name & ".ads");
    else
      for child in Child_Range loop
        case mode is
          when all_in_spec   => with_in_spec (child) := True;
          when mixed         => with_in_spec (child) := Rnd > 0.5;
          when all_in_bodies => with_in_spec (child) := False;
        end case;
      end loop;
      --
      for is_body in Boolean loop
        if is_body then
          Create (f, file_name & ".adb");
        else
          Create (f, file_name & ".ads");
        end if;
        Put_Line (f, "--  File generated by Pkg_Demo_Gen. This is needed for Pkg_Demo.");
        Put_Line (f, "--");
        if depth < max_depth then
          New_Line (f);
          for child in Child_Range loop
            if is_body xor with_in_spec (child) then
              Put_Line (f, "with " & name & Image (child) & ';');
            end if;
          end loop;
        end if;
        if not is_body then
          New_Line (f);
          Put_Line (f, "with HAL; use HAL;");
        end if;
        New_Line (f);
        Put (f, "package ");
        if is_body then
          Put (f, "body ");
        end if;
        Put_Line (f, name & " is");
        New_Line (f);
        Put (f, "  function Do_it return VString");
        if is_body then
          Put_Line (f, "  is");
          Put_Line (f, "  begin");
          Put_Line (f, "    return +""[" & prefix & "]""");
          if depth < max_depth then
            --  Now the funny part...
            for child in Child_Range loop
              Put_Line (f, "   & " & name & Image (child) & ".Do_it");
            end loop;
          end if;
          Put_Line (f, "    ;");
          Put_Line (f, "  end Do_it;");
        else
          Put_Line (f, ';');
        end if;
        New_Line (f);
        Put_Line (f, "end " & name & ';');
        Close (f);
        --
      end loop;
    end if;
    if depth < max_depth then
      --  Now the funny part...
      for child in Child_Range loop
        Generate (prefix & Image (child), depth + 1, mode);
      end loop;
    end if;
  end Generate;

  abbr : array (Test_Mode) of Character;

begin
  abbr (all_in_spec)   := 'S';
  abbr (mixed)         := 'M';
  abbr (all_in_bodies) := 'B';

  for mode in Test_Mode loop
    Generate (+abbr (mode), 0, mode);
  end loop;
end Pkg_Demo_Gen;
