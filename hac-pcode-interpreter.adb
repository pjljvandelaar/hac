with HAC.Data;

with Ada.Unchecked_Deallocation;
with Ada.Calendar;                      use Ada.Calendar;
with Ada.Text_IO;                       use Ada.Text_IO;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Numerics.Float_Random;         use Ada.Numerics.Float_Random;

package body HAC.PCode.Interpreter is

  package IIO is new Integer_IO (Integer);
  use IIO;
  package FIO is new Float_IO(Float);
  use FIO;
  package Boolean_Text_IO is new Enumeration_IO(Boolean);
  use Boolean_Text_IO; -- [P2Ada]: This is for 'Write([Boolean])'

  package InterDef is -- sub-package, was a separate Turbo Pascal unit

    --  DaysPast:array ( 1 .. 12 ) of  integer := --  Does not account for leap year

    --  (    0,  31,  59,  90, 120, 151, 181, 212, 243, 273, 304, 335  );
    --  Jan  Feb  Mar  Apr  May  Jun  Jul  Aug  Sep  Oct  Nov  Dec


     NilTask:integer:= -1 ;


  subtype
    TRange          is integer  range 0 .. HAC.Data.TaskMax ; --  task index

     type ProcessorState  is  (
       CASCHK,
       -- ConstErr,
       DEADLOCK, DIVCHK, FIN,
                      INXCHK,
                      -- NumErr  ,
       ProgErr , REDCHK, RUN,
                      STKCHK,
       -- StoErr  , TaskErr ,
       WAIT ) ;
    type TaskState       is  ( Completed, Delayed, Ready, Running,
                       Critical, WaitRendzv, WaitSem,
                       TimedRendz, TimedWait, Terminated ) ;

    type PriCB           is   record  --  Priority Control Block

     UPRI    : integer ; --  User specified priority

     INHERIT : boolean ; --  Priority inheritance enabled

     end record ;
    type GRegister       is   record   --  General register
      B : BOOLEAN;
      C : Character;
      I : INTEGER;
      R : Float;
    end record ;

    subtype Data_Type is GRegister;

    --  Stack
    S: array ( 1 .. HAC.Data.STMAX ) of Data_type;
    --  array table
    ATAB:array ( 1 .. HAC.Data.AMAX ) of  HAC.Data.ATABEntry ;
    --  block table
    BTAB: array ( 1 .. HAC.Data.BMAX ) of  HAC.Data.BTABEntry ;
    --  object code table
    CODE: array ( 0 .. HAC.Data.CDMAX ) of  HAC.Data.ORDER ;
    --  string table
    STAB: array ( 0 .. HAC.Data.SMAX ) of  Character ;
    --  identifier table
    TAB : array ( 0 .. HAC.Data.TMAX ) of  HAC.Data.TABEntry ;
    --  Float constant table
    FCTAB:array ( 1 .. HAC.Data.C2MAX ) of  Float ;
    --  Task Table
    TaskTAB:array ( 0 .. HAC.Data.TaskMax ) of  HAC.Data.INDEX ;

    subtype file_rng is integer range 0 .. HAC.Data.FMAX;

    type FFiles is array ( 1 .. HAC.Data.FMAX ) of  Ada.Text_IO.File_Type;
    type FNames is array ( 1 .. HAC.Data.FMAX ) of  string (1 ..HAC.Data.ALNG);

    type FilDescr   is   record
      CURR  : integer                          ;
      KOUNT : file_rng                         ;  --  short
      FIL   : FFiles ;
      NAM   : FNames;
    end record ;

    FAT: FilDescr;                     --  file i/o table

    type Display_type is array ( 1 .. HAC.Data.LMAX ) of  integer ;

    type TCBrec          is   record   --  Task Control Block

     --  index of current top of stk

     T         : integer                    ;
                       --  index of current base of stk

     B         : integer                    ;
                       --  program counter, next pcode

     PC        : integer                    ;
                       --  current task state

     TS        : TaskState                  ;
                       --  task in rendz with or -1

     InRendzv  : integer                    ;
                       --  end of delay period

     WAKETIME  : time                       ;
                       --  task priority parameter rec.

     Pcontrol  : PriCB                      ;
                       --  millisecond time slice

     QUANTUM   : Duration; -- time                       ;
                       --  time last run end (fairness)

     LASTRUN   : time                       ;
                       --  binding

     DISPLAY   : Display_type;
                       --  stack overflow if exceeded

     STACKSIZE : integer                    ;
                       --  id of object suspended on

     SUSPEND   : integer                    ;
                       --  general use registers

     R1,R2,R3  : GRegister                  ;
                     end record                                 ;
    type Enode;
    type Eptr is access Enode; --  task entry rendzv pointer

     type Enode           is   record        --  task entry structure

     P2Ada_no_keyword_Task : TRange ; --  index of task enqueued for rendzv

     Next : Eptr   ; --  next entry in list

     end record ;

     procedure Dispose is new Ada.Unchecked_Deallocation(Enode, Eptr) ;


    type EHeader         is   record
                       P2Ada_no_keyword_Task  : TRange ; --  index of task that contains entry

     First : Eptr   ; --  ptr to first node in rendzv queue

     Last  : Eptr   ; --  ptr to last  node in rendzv queue

     end record ;



             IR:HAC.Data.ORDER; --  instruction register


     PS:ProcessorState; --  processor status register
     TCB:array ( TRange ) of  TCBrec ; --  Task control blocks
     EList:array ( 1 .. HAC.Data.EntryMax ) of  EHeader ; --  Entry queue array
     SWITCH:boolean; --  invoke scheduler on next cycle flag
     SYSCLOCK:time;    --  ms after 00:00:00 Jan 1, current year
     TIMER:time;    --  set to end of current task's time slice
     TActive:TRange;  --  no. of active tasks


     CurTask:integer; --  index of currently executing task


     H1,H2:integer;
          H3,H4:integer;
          H5:integer;
             F1:Float;
         BLKCNT:integer;

     NCALLS:INTEGER;   --  AVL  TERMINATE


     NCOMPL:INTEGER;   --  AVL  TERMINATE

       function GetClock return Time renames Clock;

     end InterDef;

     procedure  INTERPRET  --  Global Data Used :
     --       CODE     : Code table, psuedo instructions
     --       S        : Stack
     --       TAB      : Table of all identifiers
     --       ATAB     : Array table
     --       BTAB     : Block table
     --       FAT      : File I/O table
     --       FCTAB    : Floating point constant table
     --       STAB     : String table
     --       TaskTAB  : table of Task definitions
     --       EntryTab : task Entry table
      is
      Start_Time: constant Time:= Clock;
               --  trap label
        Gen: Generator;

     function  AnyTaskDelayed return  boolean is
     Result_AnyTaskDelayed : boolean;

                      t: InterDef.TRange;
           taskdelayed:boolean;

       use InterDef;

    begin
      taskdelayed := FALSE ;
      t := 0 ;
      while t <= HAC.Data.TCount  and  not taskdelayed loop
        taskdelayed :=
          TCB (t).ts = Delayed or
          TCB (t).ts = TimedRendz or
          TCB (t).ts = TimedWait;
        t := t + 1 ;
      end loop;
      Result_AnyTaskDelayed := taskdelayed ;
     return Result_AnyTaskDelayed;
     end AnyTaskDelayed;
     pragma Unreferenced (AnyTaskDelayed);

     function  EIndex(P2Ada_no_keyword_Entry : Integer)  return  Integer


       is
     Result_EIndex : Integer;

            i,e:integer;


    begin
      e := -1 ;
      i := 1 ;
      while ((i <= HAC.Data.ECount)  and  (e = -1)) loop

        if  (P2Ada_no_keyword_Entry = HAC.Data.EntryTAB (i)) then

          e := i ;
         end if;
        i := i + 1 ;
      end loop;
      Result_EIndex := e ;
     return Result_EIndex;
     end EIndex;   --  EIndex



     procedure  Queue(P2Ada_no_keyword_Entry : Integer ; CallingTask : InterDef.TRange)
       is
            ix:integer;
              enode_var: InterDef.Eptr;
      use InterDef;
    begin  --  Queue an entry call by CallingTask for entry 'Entry'.

     ix := EIndex (P2Ada_no_keyword_Entry) ;
       enode_var:= new InterDef.Enode;
      enode_var.all.P2Ada_no_keyword_task := CallingTask ;
      enode_var.all.next := null ;
       -- [P2Ada]: WITH instruction
     declare
         P2Ada_Var_1 : InterDef.EHeader renames InterDef.Elist(ix);
     begin

        if  P2Ada_Var_1.First = null then

          P2Ada_Var_1.First := enode_var ;

        else

          P2Ada_Var_1.Last.all.next := enode_var ;
        end if;
        P2Ada_Var_1.Last := enode_var ;

     end; -- [P2Ada]: end of WITH

    end Queue;  --  Queue



     function  FirstCaller(P2Ada_no_keyword_Entry : Integer)  return  Integer


       is
     Result_FirstCaller : Integer;

            ix,val:integer;

       use InterDef;
    begin
      ix := EIndex (P2Ada_no_keyword_Entry) ;
      if  (InterDef.Elist (ix).first = null) then

        val := -1 ;

      else

        val := InterDef.Elist (ix).first.all.P2Ada_no_keyword_task ;
      end if;
      Result_FirstCaller := val ;
     return Result_FirstCaller;
     end FirstCaller;   --  FirstCaller



     function  RemoveFirst(P2Ada_no_keyword_Entry : Integer)  return  InterDef.TRange


       is
     Result_RemoveFirst : InterDef.TRange;

            ix,val:integer;
                  dmy: InterDef.Eptr;
      use InterDef;
    begin
      ix := EIndex (P2Ada_no_keyword_Entry) ;
       -- [P2Ada]: WITH instruction
     declare
          P2Ada_Var_2 : InterDef.EHeader renames InterDef.Elist(ix);
     begin

        Val := P2Ada_Var_2.First.all.P2Ada_no_keyword_task ;
        if  P2Ada_Var_2.First = P2Ada_Var_2.Last then

          P2Ada_Var_2.First := null ;
          P2Ada_Var_2.Last := null ;

        else

          dmy := P2Ada_Var_2.First ;
          P2Ada_Var_2.First := P2Ada_Var_2.First.all.Next ;
          InterDef.dispose (dmy);
        end if;

     end; -- [P2Ada]: end of WITH

      Result_RemoveFirst := val ;
     return Result_RemoveFirst;
     end RemoveFirst;   --  RemoveFirst



     procedure  ShowQ(P2Ada_no_keyword_Entry : Integer)  --  for debugging



      is

               p: InterDef.Eptr;
           ix:integer;

      use InterDef;

    begin
      ix := EIndex (P2Ada_no_keyword_Entry) ;
      p := InterDef.EList (ix).First ;
          Put("Dumping q for entry ");
     Put(TAB(P2Ada_no_keyword_Entry).NAME);
     Put(" entry index=");
     Put(ix); New_Line;
      if  p /= null then

        loop
              Put("Task ");
     Put(TAB(TaskTAB(p.all.P2Ada_no_keyword_task)).NAME); New_Line;
          p := p.all.next ;
           exit when p = null ;
        end loop;

      else

         Put("*** EMPTY ***"); New_Line;
      end if;
    end ShowQ;  --  ShowQ
    pragma Unreferenced (ShowQ);



     procedure  Purge(P2Ada_no_keyword_Entry : Integer ; t : InterDef.TRange)


       is

              p,q: InterDef.Eptr;     --  has timed out, the entry

     ix:integer;     --  is purged from the q.

        use InterDef;

     begin
      ix := EIndex (P2Ada_no_keyword_Entry) ;
      q := null ;
      p := EList (ix).First ;
      while p /= null loop

        if  p.all.P2Ada_no_keyword_task = t then

          if  EList (ix).First = EList (ix).Last then

            ELIST (ix).First := null ;
            ELIST (ix).Last := null ;

          else if  p = EList (ix).First then

            EList (ix).First := p.all.Next ;

          else if  p = EList (ix).Last then

            EList (ix).Last := q ;
            q.all.next := null ;

          else

            q.all.next := p.all.next ;
          end if;end if;end if;
          dispose (p);
          p := null ; --  to exit loop


     else
         --  try next entry in list

     q := p ;
          p := p.all.next ;
        end if;
      end loop;
    end Purge;   --  Purge



     function  TasksToWake return  boolean


       is
     Result_TasksToWake : boolean;
            count:integer;

       use InterDef;
    begin
      count := 0 ;
      for t  in  0 .. HAC.Data.TCount loop
        if (
             TCB (t).ts = Delayed or
             TCB (t).ts = TimedRendz or
             TCB (t).ts = TimedWait
            )
            and
           SYSCLOCK >= TCB (t).WAKETIME then

          if  TCB (t).TS = TimedRendz then
            TCB (t).R1.B := FALSE ; --  timeout on rendezvous
     Purge (TCB (t).R2.I, t);  --  remove from callee's q
     end if;
          if  TCB (t).TS = TimedWait then

            TCB (t).PC := TCB (t).R1.I ; --  t.out on accept

     end if;
          TCB (t).TS := Ready ;
          count := count + 1 ;
         end if;
      end loop;
      Result_TasksToWake := (count > 0) ;
     return Result_TasksToWake;
     end TasksToWake;   --  TasksToWake


     --  $I sched.pas
     --  This file contains the different scheduling strategies


     --  ========================================================================
     --  SmallAda Pcode Interpreter
     --  ========================================================================

    use InterDef;

  begin --  INTERPRET

    loop --  until Processor state <> RUN

     SYSCLOCK := GetCLOCK ;
      if HAC.Data.SNAP then
         null; -- ShowTime ;
       end if;
      if  InterDef.TCB (InterDef.CurTask).TS = InterDef.Critical then

        if HAC.Data.SNAP then

          null; -- SnapShot ;
         end if;

      else if InterDef.SWITCH or  --  ------------> Voluntary release of control

     InterDef.SYSCLOCK >= InterDef.TIMER or  --  ---> Time slice exceeded

     TasksToWake then --  ------> Awakened task causes switch


     if InterDef.CurTask >= 0 then

          TCB (CurTask).LASTRUN := SYSCLOCK ;
          if  (TCB (CurTask).TS = Running) then

            TCB (CurTask).TS := Ready ;
            --  SWITCH PROCCESS
           end if;
         end if;
        loop --  Call Main Scheduler
          --  Schedule(Scheduler,CurTask, PS);
          InterDef.SYSCLOCK := GetCLOCK ;
          if HAC.Data.SNAP then
             null; --ShowTime ;
           end if;
          if HAC.Data.SNAP then
            null; -- SnapShot ;
           end if;
           exit when PS /= WAIT ;
        end loop;
        if  PS = DEADLOCK or PS = FIN  then
          goto LABEL_123777;
         end if;
        TIMER := InterDef.SYSCLOCK + InterDef.TCB (InterDef.CurTask).QUANTUM ;
        InterDef.TCB (InterDef.CurTask).TS := Running ;
        SWITCH := FALSE ;
        if HAC.Data.SNAP then
          null; -- SnapShot ;
         end if;
       end if;end if;
      --  FETCH INSTRUCTION

      -- [P2Ada]: WITH instruction
     declare
          P2Ada_Var_5 : InterDef.TCBrec renames InterDef.TCB(InterDef.CurTask);
     begin

        InterDef.IR := CODE (P2Ada_Var_5.PC) ;
        P2Ada_Var_5.PC := P2Ada_Var_5.PC + 1 ;

     end; -- [P2Ada]: end of WITH

      --  HERE IS THE POINT WHERE THE TASK MONITORING IS CALLED
      -- (removed)

       -- [P2Ada]: WITH instruction
     declare
          P2Ada_Var_6 : InterDef.TCBrec renames InterDef.TCB(InterDef.CurTask);
     begin

        case  InterDef.IR.F  is
     when
          0 =>
           --  load address

     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
            if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              S (P2Ada_Var_6.T).I := P2Ada_Var_6.DISPLAY (IR.X) + IR.Y ;
            end if;

          when 1 => --  PUSHV - load value


     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
            if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              S (P2Ada_Var_6.T) := S (P2Ada_Var_6.DISPLAY (IR.X) + IR.Y) ;
            end if;

          when 2 => --  PUSHI - load indirect value


     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
            if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              S (P2Ada_Var_6.T) := S (S (P2Ada_Var_6.DISPLAY (IR.X) + IR.Y).I) ;
            end if;

          when 3 => --  UPDV - update display vector

     H1 := IR.Y ;
            H2 := IR.X ;
            H3 := P2Ada_Var_6.B ;
            loop
              P2Ada_Var_6.DISPLAY (H1) := H3 ;
              H1 := H1 - 1 ;
              H3 := S (H3 + 2).I ;
               exit when (H1 = H2) ;
        end loop;

          when 4 => --  ACCR - accept rendezvous      (* Hathorn, Cramer

     H1 := IR.Y ;                    --  entry pointer
     H2 := FirstCaller (H1) ;        --  first waiting task
     H3 := TAB (H1).LEV ;            --  level of accepting entry

     if  H2 >= 0 then
                      --  start rendzv if call is waiting

     P2Ada_Var_6.DISPLAY (H3 + 1) := TCB (H2).B ; --  address callers parms

     P2Ada_Var_6.InRendzv := H2 ;  --  indicate that task is in Rendzv

     if  TCB (H2).TS = TimedRendz then
                TCB (H2).TS := WaitRendzv ;
               end if;
            else
                                 --  or put self to sleep
     P2Ada_Var_6.SUSPEND := H1 ;
              P2Ada_Var_6.TS := WaitRendzv ;      --  status is waiting for rendezvous
              P2Ada_Var_6.PC := P2Ada_Var_6.PC - 1 ;          --  do this step again when awakened

     end if;
            SWITCH := TRUE ;
            --  accept rendezvous

     when 5 => --  ENDR - end rendezvous
     --  Hathorn



     P2Ada_Var_6.InRendzv := NilTask ;          --  indicate rendezvous has ended

     H1 := IR.Y ;                   --  entry pointer

     H2 := RemoveFirst (H1) ;       --  waiting task pointer

     if  H2 >= 0 then
                      --  wake up waiting task

     TCB (H2).SUSPEND := 0 ;
              TCB (H2).TS := Ready ;
              SWITCH := TRUE ;
             end if;
             --  end rendezvous

     when 6 => --  P(S) - wait semaphore



     H1 := S(P2Ada_Var_6.T).I ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            if  S (H1).I > 0 then

              S (H1).I := S (H1).I - 1 ;
              P2Ada_Var_6.TS := Critical ;   --  In a critical section, task gets

                           --  exclusive access to the virtual
     else
                         --  processor until section ends.
     P2Ada_Var_6.SUSPEND := H1 ;
              P2Ada_Var_6.TS := WaitSem ;
              SWITCH := TRUE ;
            end if;

          when 7 => --  V(S) - signal semaphore



     H1 := S (P2Ada_Var_6.T).I ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            H2 := HAC.Data.TCount + 1 ;
            H3 := Integer (RANDOM(gen) * Float(H2)) ;
            while (H2 >= 0)  and
                  (TCB (H3).TS /= WaitSem)  and
                  (TCB (H3).SUSPEND /= H1) loop

              H3 := (H3 + 1)  mod  (HAC.Data.TaskMax + 1) ;
              H2 := H2 - 1 ;
            end loop;
            if  (H2 < 0)  or  (S(H1).I < 0)
            then

              S (H1).I := S (H1).I + 1 ;

            else

              TCB (H3).SUSPEND := 0 ;
              TCB (H3).TS := Ready ;
            end if;
            P2Ada_Var_6.TS := Ready ; --  end critical section

            SWITCH := TRUE ;

          when 8 => --  STDF - standard functions


     case  IR.Y  is
     when
              0 =>

                S (P2Ada_Var_6.T).I := ABS (S (P2Ada_Var_6.T).I) ;

              when 1 =>


                S (P2Ada_Var_6.T).R := ABS (S (P2Ada_Var_6.T).R) ;

              when 2 =>


                S (P2Ada_Var_6.T).I := ( (S (P2Ada_Var_6.T).I)**2) ;

              when 3 =>


                S (P2Ada_Var_6.T).R := ( (S (P2Ada_Var_6.T).R)**2) ;

              when 4 =>


                S (P2Ada_Var_6.T).B := ( (S (P2Ada_Var_6.T).I) mod 2 /= 0) ;

              when 5 =>
               --  S[T].C := CHR(S[T].I);


     if  (S (P2Ada_Var_6.T).I < HAC.Data.OrdMinChar)
                     or  (S (P2Ada_Var_6.T).I > HAC.Data.OrdMaxChar) then

                  PS := INXCHK ;
                 end if;

              when 6 =>


                S (P2Ada_Var_6.T).I := Character'Pos (S (P2Ada_Var_6.T).C) ;

              when 7 =>


                S (P2Ada_Var_6.T).C := Character'Succ (S (P2Ada_Var_6.T).C) ;

              when 8 =>


                S (P2Ada_Var_6.T).C := Character'Pred (S (P2Ada_Var_6.T).C) ;

              when 9 =>


                S (P2Ada_Var_6.T).I := Integer (S (P2Ada_Var_6.T).R) ;

              when 10 =>


                S (P2Ada_Var_6.T).I := Integer (S (P2Ada_Var_6.T).R) ;

              when 11 =>


                S (P2Ada_Var_6.T).R := SIN (S (P2Ada_Var_6.T).R) ;

              when 12 =>


                S (P2Ada_Var_6.T).R := COS (S (P2Ada_Var_6.T).R) ;

              when 13 =>


                S (P2Ada_Var_6.T).R := EXP (S (P2Ada_Var_6.T).R) ;

              when 14 =>


                S (P2Ada_Var_6.T).R := Log (S (P2Ada_Var_6.T).R) ;

              when 15 =>


                S (P2Ada_Var_6.T).R := SQRT (S (P2Ada_Var_6.T).R) ;

              when 16 =>


                S (P2Ada_Var_6.T).R := ARCTAN (S (P2Ada_Var_6.T).R) ;

              when 17 =>

                P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
                if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

                  PS := STKCHK ;

                else if  (IR.X = 0) then

                  S (P2Ada_Var_6.T).B := End_of_File ;

                else

                  S (P2Ada_Var_6.T).B := End_of_File (FAT.FIL (IR.X)) ;
                end if;end if;

              when 18 =>

                P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
                if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

                  PS := STKCHK ;

                else if  (IR.X = 0) then

                  S (P2Ada_Var_6.T).B := End_of_Line ;

                else

                  S (P2Ada_Var_6.T).B := End_of_Line (FAT.FIL (IR.X)) ;
                end if;end if;

              when 19 =>


                S (P2Ada_Var_6.T).I := Integer(RANDOM(gen) * Float((S(P2Ada_Var_6.T).I + 1))) ;

              when 100 =>
               --  CLOCK function, NILADIC functions have IR.Y => 100

     --  Return time of units of seconds.

     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
                if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

                  PS := STKCHK ;

                else

                  S (P2Ada_Var_6.T).R := Float(GetCLOCK - Start_Time);
                end if;

            when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;


          when 9 => --  OFFS - offset


     S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I + IR.Y ;

          when 10 => --  JMP - jump



     P2Ada_Var_6.PC := IR.Y ;

          when 11 => --  JMPC - conditional jump



     if  not S (P2Ada_Var_6.T).B then

              P2Ada_Var_6.PC := IR.Y ;
             end if;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

          when 12 => --  SWTC - switch



     H1 := S (P2Ada_Var_6.T).I ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            H2 := IR.Y ;
            H3 := 0 ;
            loop
              if  CODE (H2).F /= 13 then

                H3 := 1 ;
                PS := CASCHK ;

              else

                if CODE (H2).Y = H1 or CODE (H2).X < 0 then

                  H3 := 1 ;
                  P2Ada_Var_6.PC := CODE (H2 + 1).Y ;

                else

                  H2 := H2 + 2 ;
                end if;
              end if;
               exit when ( H3 /= 0 );
        end loop;

          when 14 => --  FOR1



     H1 := S (P2Ada_Var_6.T - 1).I ;
            if  H1 <= S (P2Ada_Var_6.T).I then

              S (S (P2Ada_Var_6.T - 2).I).I := H1 ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;
              P2Ada_Var_6.PC := IR.Y ;
            end if;

          when 15 => --  FOR2



     H2 := S (P2Ada_Var_6.T - 2).I ;
            H1 := S (H2).I + 1 ;
            if  H1 <= S (P2Ada_Var_6.T).I then

              S (H2).I := H1 ;
              P2Ada_Var_6.PC := IR.Y ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;
            end if;

          when 16 => --  for1rev



     H1 := S (P2Ada_Var_6.T).I ;
            if  H1 >= S (P2Ada_Var_6.T - 1).I then

              S (S (P2Ada_Var_6.T - 2).I).I := H1 ;

            else

              P2Ada_Var_6.PC := IR.Y ;
              P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;
            end if;

          when 17 =>
           --  for2rev


     H2 := S (P2Ada_Var_6.T - 2).I ;
            H1 := S (H2).I - 1 ;
            if  H1 >= S (P2Ada_Var_6.T - 1).I then

              S (H2).I := H1 ;
              P2Ada_Var_6.PC := IR.Y ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;
            end if;

          when 18=>
           --  mark stack


     H1 := BTAB (TAB (IR.Y).REF).VSIZE ;
            if  P2Ada_Var_6.T + H1 > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T + 5 ; --  make room for fixed area

     S (P2Ada_Var_6.T - 1).I := H1 - 1 ; --  vsize-1

     S (P2Ada_Var_6.T).I := IR.Y ;   --  TAB index of called procedure/entry

     end if;

          when 19 =>
           --  procedure and task entry CALL
     --  Cramer


     if  IR.X = HAC.Data.CallTMDE then
             --  Timed entry call

     F1 := S (P2Ada_Var_6.T).R ; --  Pop delay time

     P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
             end if;
            H1 := P2Ada_Var_6.T - IR.Y ;     --  base of activation record

     H2 := S (H1 + 4).I ; --  TAB index of called procedure/entry

     H3 := TAB (H2).LEV ;
            P2Ada_Var_6.DISPLAY (H3 + 1) := H1 ;
            S (H1 + 1).I := P2Ada_Var_6.PC ; --  return address

     H4 := S (H1 + 3).I + H1 ; --  new top of stack

     S (H1 + 2).I := P2Ada_Var_6.DISPLAY (H3) ; --  static link

     S (H1 + 3).I := P2Ada_Var_6.B ; --  dynamic link

     for H3  in    P2Ada_Var_6.T+1 .. H4 loop

              S (H3).I := 0 ; --  initialize local vars

     end loop;
            P2Ada_Var_6.B := H1 ;
            P2Ada_Var_6.T := H4 ;
            case  IR.X  is
     when  --  Call type

     HAC.Data.CallSTDP =>
               --  Standard procedure call

     P2Ada_Var_6.PC := TAB (H2).ADR ;

              when HAC.Data.CallSTDE =>
               --  Unconditional entry call

     Queue (H2, CurTask);          --  put self on entry queue

     P2Ada_Var_6.TS := WaitRendzv ;
                H5 := TAB (H2).ADR ;              --  Task being entered

     if  ((TCB (H5).TS = WaitRendzv)  and  (TCB (H5).SUSPEND = H2))
                     or  (TCB (H5).TS = TimedWait) then
                           --  wake accepting task if necessayr

     TCB (H5).TS := Ready ;
                  TCB (H5).SUSPEND := 0 ;
                 end if;
                SWITCH := TRUE ;                 --  give up control


     when HAC.Data.CallTMDE =>
               --  Timed entry call

     Queue (H2, CurTask);    --  put self on entry queue

     H5 := TAB (H2).ADR ;    --  Task being entered

     if  ((TCB (H5).TS = WaitRendzv)  and  (TCB (H5).SUSPEND = H2))
                     or  (TCB (H5).TS = TimedWait) then
                           --  wake accepting task if necessary

     P2Ada_Var_6.TS := WaitRendzv ;     --  suspend self

                  TCB (H5).TS := Ready ;  --  wake accepting task

                  TCB (H5).SUSPEND := 0 ;

                else

                  P2Ada_Var_6.TS := TimedRendz ;     --  Timed Wait For Rendezvous

                  P2Ada_Var_6.R1.B := TRUE ;         --  Init R1 to specify NO timeout

     P2Ada_Var_6.R2.I := H2 ;           --  Save address of queue for purge

     SYSCLOCK := GetCLOCK ; --  update System Clock

     P2Ada_Var_6.WAKETIME := SYSCLOCK + Duration(F1 * 1000.0) ;
                  --  internal time units is milliseconds so X 1000.0

     end if;
                SWITCH := TRUE ;       --  give up control


     when HAC.Data.CallCNDE =>
               --  Conditional Entry Call

     H5 := TAB (H2).ADR ;              --  Task being entered

     if  ((TCB (H5).TS = WaitRendzv)  and  (TCB (H5).SUSPEND = H2))
                     or  (TCB(H5).TS = TimedWait) then

                  Queue (H2, CurTask);    --  put self on entry queue

     P2Ada_Var_6.R1.B := TRUE ;         --  Indicate entry successful

     P2Ada_Var_6.TS := WaitRendzv ;
                  TCB (H5).TS := Ready ;  --  wake accepting task if required

                  TCB (H5).SUSPEND := 0 ;
                  SWITCH := TRUE ;       --  give up control


     else
                 --  can't wait, forget about entry call

     P2Ada_Var_6.R1.B := FALSE ; --  Indicate entry failed in R1 1

     --  failure will be acknowledged by next instruction, 32

     end if;

            when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;


          when 20 =>
           --  INDEX1


     H1 := IR.Y ;     --  H1 points to ATAB

     H2 := ATAB (H1).LOW ;
            H3 := S (P2Ada_Var_6.T).I ;
            if  H3 < H2 then

              PS := INXCHK ;

            else if  H3 > ATAB (H1).HIGH then

              PS := INXCHK ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
              S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I + (H3 - H2) ;
            end if;end if;

          when 21 =>
           --  INDEX


     H1 := IR.Y ;      --  H1 POINTS TO ATAB

     H2 := ATAB (H1).LOW ;
            H3 := S (P2Ada_Var_6.T).I ;
            if  H3 < H2 then

              PS := INXCHK ;

            else if  H3 > ATAB (H1).HIGH then

              PS := INXCHK ;

            else

              P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
              S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I + (H3 - H2) * ATAB (H1).ELSIZE ;
            end if;end if;

          when 22 =>
           --  load block


     H1 := S (P2Ada_Var_6.T).I ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            H2 := IR.Y + P2Ada_Var_6.T ;
            if  H2 > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              while P2Ada_Var_6.T < H2 loop

                P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
                S (P2Ada_Var_6.T) := S (H1) ;
                H1 := H1 + 1 ;
              end loop;
            end if;

          when 23 =>
           --  copy block


     H1 := S (P2Ada_Var_6.T - 1).I ;
            H2 := S (P2Ada_Var_6.T).I ;
            H3 := H1 + IR.Y ;
            while H1 < H3 loop

              S (H1) := S (H2) ;
              H1 := H1 + 1 ;
              H2 := H2 + 1 ;
            end loop;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 2 ;

          when 24 =>
           --  literal


     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
            if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              S (P2Ada_Var_6.T).I := IR.Y ;
            end if;

          when 25 =>
           --  load FLOAT


     P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;
            if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then

              PS := STKCHK ;

            else

              S (P2Ada_Var_6.T).R := FCTAB (IR.Y) ;
            end if;

          when 26 =>
           --  I := FLOAT(X)

     H1 := P2Ada_Var_6.T - IR.Y ;
            S (H1).R := Float(S (H1).I) ;

          when 27 =>
           --  READ


     if  (FAT.CURR = 0) then

              if  End_of_File then

                PS := REDCHK ;

              else

                case  IR.Y  is
     when
                  1 =>

                       Get(S(S(P2Ada_Var_6.T).I).I);

                  when 2 =>

                       Get(S(S(P2Ada_Var_6.T).I).R);

                  when 3 =>

                     Get(HAC.Data.CH);
                    S (S (P2Ada_Var_6.T).I).I := Character'Pos (HAC.Data.CH) ;

                  when 4 =>

                       Get(S(S(P2Ada_Var_6.T).I).C);

                when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;

              end if;
              P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

            else

              if  End_of_File (FAT.FIL (FAT.CURR)) then

                PS := REDCHK ;

              else

                case  IR.Y  is
     when
                  1 =>

                         Get(FAT.FIL(FAT.CURR),S(S(P2Ada_Var_6.T).I).I);

                  when 2 =>

                         Get(FAT.FIL(FAT.CURR),S(S(P2Ada_Var_6.T).I).R);

                  when 3 =>

                       Get(FAT.FIL(FAT.CURR),HAC.Data.CH);
                    S (S (P2Ada_Var_6.T).I).I := Character'Pos (HAC.Data.CH) ;

                  when 4 =>

                         Get(FAT.FIL(FAT.CURR),S(S(P2Ada_Var_6.T).I).C);

                when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;

              end if;
            end if;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 28 =>
           --  write STRING


     H1 := S (P2Ada_Var_6.T).I ;   --  length of string

     H2 := IR.Y ;     --  pointer to 1st char in string

     P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            loop
              if  (FAT.CURR = 0) then

                  Put(STAB(H2));

              else

                    Put(FAT.FIL(FAT.CURR),STAB(H2));
              end if;
              H1 := H1 - 1 ;        --  decrement length

     H2 := H2 + 1 ;
                                    --  increment char pointer

        exit when H1 = 0 ;
        end loop;
            SWITCH := TRUE ;        --  give up control when doing I/O


     when 29 =>
           --  write1


     if  (FAT.CURR = 0) then

              case  IR.Y  is
     when      --  Burd

     1 =>

                      Put(S(P2Ada_Var_6.T).I,10);

                when 2 =>

                      Put(S(P2Ada_Var_6.T).R,22);

                when 3 =>

                      Put(S(P2Ada_Var_6.T).B,10);

                when 4 =>

                    Put(S(P2Ada_Var_6.T).C);

              when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;


            else

              case  IR.Y  is
     when      --  Schoening

     1 =>

                        Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T).I,10);

                when 2 =>

                        Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T).R,22);

                when 3 =>

                        Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T).B,10);

                when 4 =>

                      Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T).C);

              when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;

            end if;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 30 =>
           --  write2


     if  (FAT.CURR = 0) then

              case  IR.Y  is
     when          --  Burd

     1 =>

                         Put(S(P2Ada_Var_6.T-1).I,S(P2Ada_Var_6.T).I);

                when 2 =>

                         Put(S(P2Ada_Var_6.T-1).R,S(P2Ada_Var_6.T).I);

                when 3 =>

                         Put(S(P2Ada_Var_6.T-1).B,S(P2Ada_Var_6.T).I);

                when 4 =>

                      Put(S(P2Ada_Var_6.T-1).C);

              when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;


            else

              case  IR.Y  is
     when          --  Schoening

     1 =>

                           Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T-1).I,S(P2Ada_Var_6.T).I);

                when 2 =>

                           Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T-1).R,S(P2Ada_Var_6.T).I);

                when 3 =>

                           Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T-1).B,S(P2Ada_Var_6.T).I);

                when 4 =>

                        Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T-1).C);

              when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;

            end if;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 2 ;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 32 =>
           --  EXIT entry call or procedure call
     --  Cramer


     P2Ada_Var_6.T := P2Ada_Var_6.B - 1 ;
            if  IR.Y = HAC.Data.CallSTDP then

              P2Ada_Var_6.PC := S (P2Ada_Var_6.B + 1).I ; --  Standard proc call return

     end if;
            if  P2Ada_Var_6.PC /= 0 then

              P2Ada_Var_6.B := S (P2Ada_Var_6.B + 3).I ;
              if  IR.Y = HAC.Data.CallTMDE or IR.Y = HAC.Data.CallCNDE  then

                if  (IR.Y = HAC.Data.CallTMDE)  and  (P2Ada_Var_6.R1.B = FALSE) then

                  P2Ada_Var_6.T := P2Ada_Var_6.T + 1 ;        --  A JMPC instruction always follows

     end if;
                if  P2Ada_Var_6.T > P2Ada_Var_6.STACKSIZE then --  timed and conditional entry call


     PS := STKCHK ;      --  returns (32).  Push entry call
     else
                  S (P2Ada_Var_6.T).B := P2Ada_Var_6.R1.B ;   --  success indicator for JMPC.
     end if;
               end if;
            else
              TActive := TActive - 1 ;
              P2Ada_Var_6.TS := Completed ;
              SWITCH := TRUE ;
            end if;
            --  RETURN

     when 33 =>
           --  EXIT function


     P2Ada_Var_6.T := P2Ada_Var_6.B ;
            P2Ada_Var_6.PC := S (P2Ada_Var_6.B + 1).I ;
            P2Ada_Var_6.B := S (P2Ada_Var_6.B + 3).I ;
            if  (IR.Y < 0) then

              PS := ProgErr ;
             end if;

          when 34 =>

            S (P2Ada_Var_6.T) := S (S (P2Ada_Var_6.T).I) ;

          when 35 =>

            S (P2Ada_Var_6.T).B := not S (P2Ada_Var_6.T).B ;

          when 36 =>

            S (P2Ada_Var_6.T).I := - S(P2Ada_Var_6.T).I ;

          when 37 =>
            --  write FLOAT


     if  (FAT.CURR = 0) then

                          Put(S(P2Ada_Var_6.T-2).R,S(P2Ada_Var_6.T-1).I,S(P2Ada_Var_6.T).I,0);

            else


                       Put(FAT.FIL(FAT.CURR),S(P2Ada_Var_6.T-2).R,S(P2Ada_Var_6.T-1).I,S(P2Ada_Var_6.T).I,0);
            end if;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 38 =>
           --  STORE


     S (S (P2Ada_Var_6.T - 1).I) := S (P2Ada_Var_6.T) ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 2 ;

          when 39..61 =>


            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
            case  IR.F  is
     when
              39 =>


                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R = S (P2Ada_Var_6.T + 1).R) ;

              when 40 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R /= S (P2Ada_Var_6.T + 1).R) ;

              when 41 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R < S (P2Ada_Var_6.T + 1).R) ;

              when 42 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R <= S (P2Ada_Var_6.T + 1).R) ;

              when 43 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R > S (P2Ada_Var_6.T + 1).R) ;

              when 44 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).R >= S (P2Ada_Var_6.T + 1).R) ;

              when 45 =>


                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I = S (P2Ada_Var_6.T + 1).I) ;

              when 46 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I /= S (P2Ada_Var_6.T + 1).I) ;

              when 47 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I < S (P2Ada_Var_6.T + 1).I) ;

              when 48 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I <= S (P2Ada_Var_6.T + 1).I) ;

              when 49 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I > S (P2Ada_Var_6.T + 1).I) ;

              when 50 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).I >= S (P2Ada_Var_6.T + 1).I) ;

              when 51 =>


                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).B  or  S (P2Ada_Var_6.T + 1).B) ;

              when 52 =>

                S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I + S (P2Ada_Var_6.T + 1).I ;

              when 53 =>

                S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I - S (P2Ada_Var_6.T + 1).I ;

              when 54 =>


                S (P2Ada_Var_6.T).R := S (P2Ada_Var_6.T).R + S (P2Ada_Var_6.T + 1).R ;

              when 55 =>

                S (P2Ada_Var_6.T).R := S (P2Ada_Var_6.T).R - S (P2Ada_Var_6.T + 1).R ;

              when 56 =>

                S (P2Ada_Var_6.T).B := (S (P2Ada_Var_6.T).B  and  S (P2Ada_Var_6.T + 1).B) ;

              when 57 =>


                S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I * S (P2Ada_Var_6.T + 1).I ;

              when 58 =>

                if  S (P2Ada_Var_6.T + 1).I = 0 then

                  PS := DIVCHK ;

                else

                  S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I   /   S (P2Ada_Var_6.T + 1).I ;
                end if;

              when 59 =>

                if  S (P2Ada_Var_6.T + 1).I = 0 then

                  PS := DIVCHK ;

                else

                  S (P2Ada_Var_6.T).I := S (P2Ada_Var_6.T).I  mod  S (P2Ada_Var_6.T + 1).I ;
                end if;

              when 60 =>


                S (P2Ada_Var_6.T).R := S (P2Ada_Var_6.T).R * S (P2Ada_Var_6.T + 1).R ;

              when 61 =>


                S (P2Ada_Var_6.T).R := S (P2Ada_Var_6.T).R / S (P2Ada_Var_6.T + 1).R ;

            when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;
        --  case

     --  begin

     when 62 =>
            --  get newline


     if  FAT.CURR = 0 then       --  Schoening


             if  End_of_File then

                PS := REDCHK ;

              else

                 Skip_Line;
              end if;

            elsif  End_of_File (FAT.FIL (FAT.CURR)) then
              PS := REDCHK ;
            else
                Skip_Line(FAT.FIL (FAT.CURR));
            end if;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 63 =>  --  new line
     if FAT.CURR = 0 then      --  Schoening
     New_Line;
            else
                New_Line(FAT.FIL (FAT.CURR));
            end if;
            SWITCH := TRUE ;  --  give up control when doing I/O


     when 64 =>

            FAT.CURR := IR.Y ;   --  set Current File pointer


     when 65 =>
            --  File I/O procedures
     --  Schoening


     case  IR.Y  is
     when
              7 =>
                --  reset file pointer

     --  $I-

     close (FAT.FIL (IR.X));   --  just in case

     H1 := 0; -- was IOresult ;   --  clears any I/O error

     Open (FAT.FIL (IR.X), In_File, FAT.NAM (IR.X) & ".DAT");

              when 8 =>
                --  rewrite file

     if Is_Open(FAT.FIL (IR.X)) then
       close (FAT.FIL (IR.X));   --  just in case
     end if;

     H1 := 0; -- IOresult ;   --  clears any I/O error

     Create (FAT.FIL (IR.X), Out_File, FAT.NAM (IR.X) & ".DAT");

              when 9 =>

                Close (FAT.FIL (IR.X));    --  close file


     when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;
       --  case IR.Y

     SWITCH := TRUE ;  --  give up control when doing I/O


     when 66=> --  Halt Interpreter



     if  TActive = 0 then
              PS := FIN ;

            else
              TCB (0).TS := Completed ;
              SWITCH := TRUE ;
              P2Ada_Var_6.PC := P2Ada_Var_6.PC - 1 ;
            end if;

          when 67 =>
             --  string assignment
     --  Hathorn


     H1 := S (P2Ada_Var_6.T - 2).I ;  --  address of array

     H2 := S (P2Ada_Var_6.T).I ;    --  pointer to string table

     H3 := IR.Y ;      --  size of array

     H4 := S (P2Ada_Var_6.T - 1).I ;  --  length of string

     if  H3 < H4 then

              H5 := H1 + H3 ;    --  H5 is H1 + min of H3, H4


     else

              H5 := H1 + H4 ;
            end if;
            while H1 < H5 loop
                        --  copy H5-H1 characters

     S (H1).I := Character'Pos (STAB (H2)) ;
              H1 := H1 + 1 ;
              H2 := H2 + 1 ;
            end loop;
            H5 := S (P2Ada_Var_6.T - 2).I + H3 ;              --  H5 = H1 + H3

     while H1 < H5 loop
                        --  fill with blanks if req'd

     S (H1).I := Character'Pos (' ') ;
              H1 := H1 + 1 ;
            end loop;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 3 ;

          when 68 =>  --  DLY - delay for a specified number of seconds



     if  S (P2Ada_Var_6.T).R > 0.0 then
                                   --  if positive delay time

     P2Ada_Var_6.TS := Delayed ;           --  set task state to delayed

     SYSCLOCK := GetCLOCK ;    --  update System Clock

     P2Ada_Var_6.WAKETIME := SYSCLOCK + Duration(S (P2Ada_Var_6.T).R * 1000.0) ; --  set wakeup time

     --  internal time units is milliseconds so X 1000.0

     SWITCH := TRUE ;          --  give up control

     end if;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;
               --  Delay

     when 69 =>  --  CURS -  CursorAt
       --  Cramer
       H2 := S (P2Ada_Var_6.T - 1).I ;  --  row
       H1 := S (P2Ada_Var_6.T).I ;      --  column
       P2Ada_Var_6.T := P2Ada_Var_6.T - 2 ; --  issue TPC call
       -- GotoXY (H1, H2);

     when 70 =>  --  QUA - Set task quantum
     --  Cramer
     if  S (P2Ada_Var_6.T).R <= 0.0 then
              S (P2Ada_Var_6.T).R := Float(HAC.Data.TSLICE) * 0.001 ;
     end if;
            TCB (Curtask).QUANTUM := Duration(S (P2Ada_Var_6.T).R) ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

          when 71 =>  --  PRI - Set task priority
     --  Cramer



     if  S (P2Ada_Var_6.T).I > HAC.Data.PriMax then

              S (P2Ada_Var_6.T).I := HAC.Data.PriMax ;
             end if;
            if  S (P2Ada_Var_6.T).I < 0 then

              S (P2Ada_Var_6.T).I := 0 ;
             end if;
            TCB (Curtask).Pcontrol.UPRI := S (P2Ada_Var_6.T).I ;
            P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

          when 72 =>  --  INHP -  Set task priority inheritance
     --  Cramer


     P2Ada_Var_6.Pcontrol.INHERIT := S (P2Ada_Var_6.T).B ; --  Set priority inherit indicator

     P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

          when 73 =>
           --  Selective Wait Macro Instruction

     case  IR.X  is
     when
              1 => --  Start Selective Wait seq.


     TCB (CurTask).R1.I := 0 ; --  next instruction if delay expires

     TCB (CurTask).R2.R := -1.0 ; --  delay time


     when 2 => --  Retain entry ID


     TCB (CurTask).R3.I := IR.Y ;

              when 3 => --  Accept if its still on queue



     H1 := TCB (CurTask).R3.I ;
                H2 := FirstCaller (H1) ;    --  first waiting task

     H3 := TAB (H1).LEV ;        --  level of accepting entry

     if  H2 >= 0 then

                  P2Ada_Var_6.DISPLAY (H3 + 1) := TCB (H2).B ; --  address callers parms

     P2Ada_Var_6.InRendzv := H2 ;             --  indicate task InRendz

     if  TCB (H2).TS = TimedRendz then --  turn off entry timeout


     TCB (H2).TS := WaitRendzv ;    --  if it was on
                   end if;
                else
                  P2Ada_Var_6.PC := IR.Y ; --  Jump to patched in address
     end if;
                SWITCH := TRUE ;

              when 4 => --  Update minimum delay time

     if  S (P2Ada_Var_6.T).R > 0.0 then

                  if  TCB (CurTask).R2.R = -1.0
                  then

                    TCB (CurTask).R2.R := S (P2Ada_Var_6.T).R ;
                    TCB (CurTask).R1.I := IR.Y ;   --  ins after JMP


     else if  S (P2Ada_Var_6.T).R < TCB (CurTask).R2.R then

                    TCB (CurTask).R2.R := S (P2Ada_Var_6.T).R ;
                    TCB (CurTask).R1.I := IR.Y ;   --  ins after JMP

     end if;end if;
                 end if;
                P2Ada_Var_6.T := P2Ada_Var_6.T - 1 ;

              when 5 |  6 => --  end of SELECT



     if  TCB (CurTask).R2.R > 0.0 then
                 --  Timed Wait

     P2Ada_Var_6.TS := TimedWait ;
                  SYSCLOCK := GetCLOCK ;
                  P2Ada_Var_6.WAKETIME := SYSCLOCK + Duration(TCB (CurTask).R2.R * 1000.0) ;
                  P2Ada_Var_6.PC := IR.Y ; --  Do SELECT again when awakened by caller

     SWITCH := TRUE ;                     --  give up control

     end if;
                --  AVL -- TERMINATE

     --  IS THE PARENT TASK COMPLETED?

     if  (TCB (0).TS = Completed)  and
                             (CURTASK /= 0)  and  (ir.x /= 6) then

                        NCALLS := 0; --  LET'S SEE IF THERE ARE CALLERS

     for ITERM  in  1 .. HAC.Data.ECount loop
                                if  ELIST(ITERM).FIRST /= null then
                                        NCALLS := NCALLS + 1;end if;
                                end loop;
                        --  YES, NO CALLERS

     if  NCALLS = 0 then  --  YES, NO CALLERS


     --  ARE THE SIBLING TASKS EITHER COMPLETED OR
     --                                   IN THE SAME STATE AS CURTASK?

     NCOMPL := 0;
                                for ITERM  in  1 .. HAC.Data.TCount loop
                                        if  TCB(ITERM).TS = Completed then
                                                NCOMPL := NCOMPL + 1
                                        ;else if  TCB(ITERM).TS = TCB(CURTASK).TS then
                                                NCOMPL := NCOMPL + 1
                                        ;else if  (TCB(ITERM).TS = Ready)  and
                                                (TCB(CURTASK).TS = Running) then
                                                NCOMPL := NCOMPL + 1;end if;end if;end if;
                                        end loop;
                                if  HAC.Data.TCount = NCOMPL then

                                        --  YES, THEN ALL TASKS ARE NOW TERMINATING

     for ITERM  in  1 .. HAC.Data.TCount loop
                                                TCB(ITERM).TS := Terminated;end loop;
                                        PS := FIN;

                                        end if;
                                end if;
                        end if;
--               if ir.x = 6 then
     --               begin
     --                 term := false ;    {Task doesn't have a terminate}
     --               end ;                {alternative}
     --


     when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;
       --  case

     --  Selective Wait

     when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;
       --  main case IR.F

     end; -- [P2Ada]: end of WITH

       exit when InterDef.PS /= InterDef.RUN ;
        end loop;
    <<LABEL_123777>>
    if  InterDef.PS /= InterDef.FIN then
      --  Post Mortem Dump of the task stack causing the exception

     New_Line;
          Put("Stack Variables of Task ");
     Put(TAB(TaskTAB(InterDef.CurTask)).Name); New_Line;
      InterDef.H1 := InterDef.TCB (InterDef.CurTask).B ;  --  current botton of stack

     InterDef.BLKCNT := 10 ;
      loop
         New_Line;
        InterDef.BLKCNT := InterDef.BLKCNT - 1 ;
        if  InterDef.BLKCNT = 0 then

          InterDef.H1 := 0 ;
         end if;
        InterDef.H2 := S (InterDef.H1 + 4).I ;    --  index into TAB for this process

     if  InterDef.H1 /= 0 then

                   Put(TAB(InterDef.H2).NAME);
     Put(" CALLED AT");
     Put(S(InterDef.H1+1).I,5); New_Line;

        else

           Put("Task Variables"); New_Line;
        end if;
        InterDef.H2 := BTAB (TAB (InterDef.H2).REF).LAST ;
        while InterDef.H2 /= 0 loop

           -- [P2Ada]: WITH instruction
     declare
          P2Ada_Var_7 : HAC.Data.TABEntry renames TAB(InterDef.H2);
          use HAC.Data;
     begin
            if  P2Ada_Var_7.OBJ = HAC.Data.VARIABLE then
              if  P2Ada_Var_7.TYP = enums or HAC.Data.STANTYPS(P2Ada_Var_7.TYP) then
                if  P2Ada_Var_7.NORMAL then
                  InterDef.H3 := InterDef.H1 + P2Ada_Var_7.ADR ;
                else
                  InterDef.H3 := InterDef.S (InterDef.H1 + P2Ada_Var_7.ADR).I ;
                end if;
                   Put("  ");
     Put(P2Ada_Var_7.NAME);
     Put(" = ");
                case  P2Ada_Var_7.TYP  is
     when
                  HAC.Data.Enums |
                  HAC.Data.INTS =>

                      Put(S(H3).I); New_Line;

                  when HAC.Data.BOOLS =>

                      Put(S(H3).B); New_Line;

                  when HAC.Data.FLOATS =>

                      Put(S(H3).R); New_Line;

                  when HAC.Data.xCHARS =>
                       Put(Character'Pos(S(H3).C));
                       Put(" ASCII"); New_Line;

                when others=> null;  -- [P2Ada]: no otherwise / else in Pascal
     end case;

               end if;
             end if;
            InterDef.H2 := P2Ada_Var_7.LINK ;

     end; -- [P2Ada]: end of WITH

        end loop;
        InterDef.H1 := InterDef.S(InterDef.H1+3).I ;
         exit when (InterDef.H1 < 0) ;
        end loop;
     end if;
    begin
   --  GotoXY (1, 20) ;

     New_Line;
       Put("Program terminated normally ..."); New_Line;
    end;

  end INTERPRET;  --  INTERPRET


 end HAC.PCode.Interpreter;
     -- Translated on 23-Jan-2013 by (New) P2Ada v. 28-Oct-2009



