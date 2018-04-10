Program wsqlite; // Originally written 2009 by G.E. Ozz Nixon Jr. @ BPDX

{$IFNDEF FPC}
   {$APPTYPE CONSOLE}
{$ENDIF}

{$IFNDEF LINUX}
  {$IFDEF POWERPC}
      {$DEFINE MAC}
  {$ELSE}
     {$IFDEF DARWIN}
        {$DEFINE MAC}
     {$ELSE}
        {$DEFINE WIN32}
     {$ENDIF}
  {$ENDIF}
{$ENDIF}
{$IFNDEF FPC}
  {$DEFINE DELPHI}
{$ELSE}
  {$MODE DELPHI}{$H+}
{$ENDIF}
{$IFDEF FPC}
   {$IFDEF UNIX}
      {$DEFINE FPC_LINUX}
      {$DEFINE FPC_MAC}
      {$DEFINE FPC_UNIX}
   {$ENDIF}
{$ENDIF}

///////////////////////////////////////////////////////////////////////////////
{.$SEFINE DESIGN1} // More of a RAW design.
{$DEFINE DESIGN2} // more of an elligant table deisgn.
{.$DEFINE USE_STRINGLIST}

{$IFDEF MAC}
   {$DEFINE USE_STRINGLIST}
{$ENDIF}

uses
   crt,
   sysutils,
{$IFDEF USE_STRINGLIST}
   classes,
{$ELSE}
   dxutil_cachearray,
{$ENDIF}
   dxutil_numeric,
   dxutil_string,
//   dxutil_exception,
   dxutil_environment,
   dxsqlite3;

{$IFDEF DESIGN2}
type
   PResultRow = ^TResultRow;
   TResultRow = Record
      ValueAddr:Cardinal; // memory location
      ValueWidth:Longint;
   End;
{$ENDIF}

var
   prompt:String;
   dbhook:TSQLiteDB;
   dbfilename:string;
   resultCode:longint;
   globalTimeout:longint;
   pageHeight:longint;
   active:boolean;
   SQL:{$IFDEF USE_STRINGLIST}TStringList{$ELSE}TDXCacheArray{$ENDIF};
   lastSQL:String;
   resultType:longint;
{$IFDEF DESIGN1}
   lineCounter:longint;
{$ENDIF}

function busy_handler_func(UserData:pointer; Counter:longint):longint;cdecl;
begin
System.Writeln('Received a busy hook! Counter=',Counter);
   Result:=0;
end;

{$IFDEF DESIGN1}
function sqlite3_callback(UserData:pointer; Columns:longint; Values:PPchar; Names:PPchar):longint; cdecl;
Var
   Loop:Integer;

begin
   if (lineCounter mod pageHeight)=0 then Begin
      For Loop:=0 to (Columns-1) do begin
         System.Write(LeftJustify(Propercase(PChar(Names^)),15)+#32);
      End;
      System.Writeln('');
      For Loop:=0 to (Columns-1) do begin
         System.Write('---------------'+#32);
      End;
      System.Writeln('');
   End;
   inc(lineCounter);
   For Loop:=0 to (Columns-1) do begin
       System.Write(LeftJustify(PChar(Values^),15)+#32);
   End;
   System.Writeln('');
   If (lineCounter=pageHeight) then begin
      System.Write('Press ENTER to continue.');
      System.Readln;
//      LineCounter:=0;
      System.Writeln('');
   End;
   Result:=0;
end;
{$ENDIF}

procedure open_database(const filename:string);
Var
   PMessage:PChar;

begin
   if Assigned(dbhook) then begin
      System.Writeln('    ^ Error! Must close database before opening another one!');
      Exit;
   End;
   dbhook := SQLite3_Malloc(4);
   if CharPos('/',Filename)=0 then begin
      resultCode := sqlite3_open(PChar(ExtractFilePath(ParamStr(0))+filename), dbhook);
   end
   else begin
      resultCode := sqlite3_open(PChar(filename), dbhook);
   end;
   if (resultCode > 0) then begin
      System.writeln('    ^ Error! Cannot open database file error'+#13#10+'      ', sqlite3_errmsg(dbhook));
      exit;
   end;
   PMessage := SQLite3_Malloc(128);
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA page_size=8192;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! page_size ',sqlite3_errmsg(dbhook));
   // 2.8.6 and older, 2000 is the default
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA cache_size=32768;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! cache_size ',sqlite3_errmsg(dbhook));
//         resultCode := SQLite3_GetTable(dbhook, PChar('PRAGMA default_cache_size=30000;'), ResultSet, Rows, Columns, PMessage);
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA synchronous=OFF;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! synchronous ',sqlite3_errmsg(dbhook));
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA count_changes=0;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! count_change ',sqlite3_errmsg(dbhook));
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA journal_mode=MEMORY;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! journal_mode ',sqlite3_errmsg(dbhook));
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA legacy_file_format=OFF;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! legacy_file ',sqlite3_errmsg(dbhook));
   resultCode := sqlite3_exec(dbhook, PChar('PRAGMA lock_mode=EXCLUSIVE;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
   if resultCode>0 then
      system.writeln('    ^ Error! lock_mode  ',sqlite3_errmsg(dbhook));
   SQLite3_free(PMessage);
end;

procedure close_database;
begin
   if Assigned(dbhook) then begin
      sqlite3_close(dbhook);
// does close free it?      SQLite3_Free(dbhook);
      dbhook := Nil;
   end;
end;

procedure doPrompt;
Var
   Ws,UpWs,Ts:String;
   PMessage:PChar;
{$IFDEF DESIGN2}
   ResultSet:TSQLiteResult;
   Rows,Columns,Loop1,Loop2:Cardinal;
   PCharPos:Pointer;
   // Prepare:
   hStmt: TSqliteStmt;
   pztail:PAnsiChar;
{$ENDIF}
{$IFNDEF USE_STRINGLIST}
   TFH:TextFile;
{$ENDIF}
   CreateTime,CreateTableTime,InsertTime,highestCommitTime,CommitTime:Comp;
   UseIndexes:Boolean;

///////////////////////////////////////////////////////////////////////////////
// From Accuracer Benchmark Source:
///////////////////////////////////////////////////////////////////////////////
function GenerateString(
                       Len : Integer // serial length
                       ) : String; // returns serial
var i,x : integer;
    s : string;
    c : char;
begin
 s := '';
 for i := 1 to len do begin
   x := Random(101);
   if ((x mod 2) =  0) then c := chr(65+(Random(260000000) mod 26))
   else c := chr(48+(Random(100000000) mod 10));
   s := s + c;
  end; //len
 result := s;
end; // GenerateString

begin
   TextColor(14);
   if not Assigned(dbhook) then prompt:='db> ';
   If SQL.Count=0 then System.Write(prompt)
   Else System.Write(RightJustify(IntegerToString(SQL.Count+1),2)+'> ');
   TextColor(15);
   System.Readln(Ws);
   TextColor(11);
   UpWs := UpperCase(Ws);
   Ts := FetchByChar(UpWs, #32);

   If Ts = 'BENCHMARK' then begin
      // BENCHMARK INSERT
      // BENCHMARK INDEXES INSERT
      // BENCHMARK CLEANUP
      // BENCHMARK EDIT
      // BENCHMARK DELETE
      close_database;
      Ts := FetchByChar(UpWs, #32);
      If Ts='CLEANUP' then begin
         if fileexists('benchmark.ozz') then deletefile('benchmark.ozz');
         Exit;
      End;
      If Ts='INDEXES' then begin
         UseIndexes:=True;
         Ts:=UpWs;
      end
      Else UseIndexes:=False;
      If (Ts='INSERT') then Begin
         CreateTime:=TimeCounter;
         open_database('benchmark.ozz');
         CreateTime:=TimeCounter-CreateTime;
         System.Writeln('Create tablespace ',trunc(CreateTime),'ms.');
         CreateTableTime:=TimeCounter;
         PMessage := SQLite3_Malloc(128);
         resultCode := SQLite3_GetTable(dbhook, PChar('CREATE TABLE TEST(ID INTEGER PRIMARY KEY AUTOINCREMENT,FSTRING VARCHAR(100),FINTEGER INTEGER);'), ResultSet, Rows, Columns, PMessage);
         if resultCode>0 then begin
            close_database;
            system.writeln('    ^ Error! Create Table: ',sqlite3_errmsg(dbhook));
            sqlite3_free(PMessage);
            exit;
         end;
         If useIndexes then Begin
            resultCode := SQLite3_GetTable(dbhook, PChar('CREATE INDEX INDEX1 ON TEST(ID);'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Create Index1: ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
            resultCode := SQLite3_GetTable(dbhook, PChar('CREATE INDEX INDEX2 ON TEST(FSTRING);'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Create Index2: ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
            resultCode := SQLite3_GetTable(dbhook, PChar('CREATE INDEX INDEX3 ON TEST(FINTEGER);'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Create Index3: ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
         end;
         CreateTableTime:=TimeCounter-CreateTableTime;
         System.Writeln('Create table structure ',trunc(CreateTableTime),'ms.');
         highestCommitTime:=0;
         InsertTime:=TimeCounter;
         For Loop1:=1 to 100000 do begin
            if (Loop1 mod 1000)=1 then begin // start transaction
               resultCode := SQLite3_GetTable(dbhook, PChar('BEGIN;'), ResultSet, Rows, Columns, PMessage);
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Start Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
            Loop2 := random (MAXInt) mod (10000);
            Ws := GenerateString(100);
            resultCode := SQLite3_GetTable(dbhook, PChar('INSERT INTO TEST(FSTRING,FINTEGER) VALUES('+#39+Ws+#39+','+IntegerToString(Loop2)+');'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Insert to transaction (',Loop1,') ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
            if (Loop1 mod 1000)=0 then begin // commit
               commitTime:=TimeCounter;
               resultCode := SQLite3_GetTable(dbhook, PChar('COMMIT;'), ResultSet, Rows, Columns, PMessage);
               commitTime:=TimeCounter-commitTime;
               if commitTime>highestCommitTime then highestCommitTime:=commitTime;
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Commit Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
         end;
         InsertTime:=TimeCounter-InsertTime;
         System.Writeln('100,000 inserts using "1,000 per transaction" took ',trunc(InsertTime),'ms.');
         System.Writeln('Slowest commit took ',trunc(highestCommitTime),'ms.');
         Close_Database;
         sqlite3_free(PMessage);
      End
      else If (Ts='EDIT') then Begin
         if not fileexists('benchmark.ozz') then begin
            system.Writeln('    ^ Error! First, you must BENCHMARK INSERT to create test rows.');
            Exit;
         end;
         CreateTime:=TimeCounter;
         open_database('benchmark.ozz');
         CreateTime:=TimeCounter-CreateTime;
         System.Writeln('Open tablespace ',trunc(CreateTime),'ms.');
         CreateTableTime:=TimeCounter;
         PMessage := SQLite3_Malloc(128);
         highestCommitTime:=0;
         InsertTime:=TimeCounter;
         For Loop1:=1 to 100000 do begin
            if (Loop1 mod 1000)=1 then begin // start transaction
               resultCode := SQLite3_GetTable(dbhook, PChar('BEGIN;'), ResultSet, Rows, Columns, PMessage);
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Start Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
            Loop2 := random (MAXInt) mod (10000);
            Ws := GenerateString(100);
            resultCode := SQLite3_GetTable(dbhook, PChar('update TEST set FSTRING='#39+Ws+#39+', FINTEGER='+IntegerToString(Loop2)+' where ID='+IntegerToString(Loop1)+';'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Update Row: ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
            if (Loop1 mod 1000)=0 then begin // commit
               commitTime:=TimeCounter;
               resultCode := SQLite3_GetTable(dbhook, PChar('COMMIT;'), ResultSet, Rows, Columns, PMessage);
               commitTime:=TimeCounter-commitTime;
               if commitTime>highestCommitTime then highestCommitTime:=commitTime;
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Commit Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
         end;
         InsertTime:=TimeCounter-InsertTime;
         System.Writeln('100,000 edits using "1,000 per transaction" took ',trunc(InsertTime),'ms.');
         System.Writeln('Slowest commit took ',trunc(highestCommitTime),'ms.');
         Close_Database;
         sqlite3_free(PMessage);
      End
      else If (Ts='DELETE') then Begin
         if not fileexists('benchmark.ozz') then begin
            system.Writeln('    ^ Error! First, you must BENCHMARK INSERT to create test rows.');
            Exit;
         end;
         CreateTime:=TimeCounter;
         open_database('benchmark.ozz');
         CreateTime:=TimeCounter-CreateTime;
         System.Writeln('Open tablespace ',trunc(CreateTime),'ms.');
         CreateTableTime:=TimeCounter;
         PMessage := SQLite3_Malloc(128);
         highestCommitTime:=0;
         InsertTime:=TimeCounter;
         For Loop1:=1 to 100000 do begin
            if (Loop1 mod 1000)=1 then begin // start transaction
               resultCode := SQLite3_GetTable(dbhook, PChar('BEGIN;'), ResultSet, Rows, Columns, PMessage);
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Start Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
            Loop2 := random (MAXInt) mod (10000);
            Ws := GenerateString(100);
            resultCode := SQLite3_GetTable(dbhook, PChar('delete from TEST where ID='+IntegerToString(Loop1)+';'), ResultSet, Rows, Columns, PMessage);
            if resultCode>0 then begin
               close_database;
               system.writeln('    ^ Error! Delete Row: ',sqlite3_errmsg(dbhook));
               sqlite3_free(PMessage);
               exit;
            end;
            if (Loop1 mod 1000)=0 then begin // commit
               commitTime:=TimeCounter;
               resultCode := SQLite3_GetTable(dbhook, PChar('COMMIT;'), ResultSet, Rows, Columns, PMessage);
               commitTime:=TimeCounter-commitTime;
               if commitTime>highestCommitTime then highestCommitTime:=commitTime;
               if resultCode>0 then begin
                  close_database;
                  system.writeln('    ^ Error! Commit Transaction ',sqlite3_errmsg(dbhook));
                  sqlite3_free(PMessage);
                  exit;
               end;
            end;
         end;
         InsertTime:=TimeCounter-InsertTime;
         System.Writeln('100,000 edits using "1,000 per transaction" took ',trunc(InsertTime),'ms.');
         System.Writeln('Slowest commit took ',trunc(highestCommitTime),'ms.');
         Close_Database;
         sqlite3_free(PMessage);
      End;
   end

   else If (Ts = 'OPEN') then begin
      SQL.Clear;
      UpWs := Ws;
      Ts := FetchByChar(UpWs, #32);
      if not fileexists(UpWs) then begin
         System.Writeln('    ^ Error! Database file does not exist.'+#13#10+
            '      Verify your path, or use the NEW <databasefile> command');
      end
      else begin
         open_database(UpWs);
         if (resultCode = 0) then begin
            System.Writeln('Database file '+UpWs+' opened.');
            prompt:=UpWs+'> ';
         end;
      End;
   end
   else if Ts = 'NEW' then begin
      SQL.Clear;
      Ts := FetchByChar(Ws, #32);
      open_database(Ws);
      if (resultCode = 0) then begin
         System.Writeln('New database file '+UpWs+' created and opened.');
         prompt:=Ws+'> ';
      end;
   end
   else if Ts = 'CLOSE' then begin
      SQL.Clear;
      if not Assigned(dbhook) then System.Writeln('    ^ Error! Database was not open.')
      else begin
         close_database;
      end;
   end
   else if Ts = 'VACUUM' then begin
      SQL.Clear;
      if not Assigned(dbhook) then System.Writeln('    ^ Error! Database was not open.')
      else begin
         PMessage := SQLite3_Malloc(128);
         resultCode := sqlite3_exec(dbhook, PChar('VACUUM;'), Nil {@sqlite3_callback}, {Self} Nil, PMessage);
         if resultCode>0 then
            system.writeln('    ^ Error! page_size ',sqlite3_errmsg(dbhook))
         else
            System.Writeln(Copy(Prompt,1,Length(Prompt)-2)+' has been optimized, dropped empty pages, expunged deletes, etc.');
      end;
   end
   else if Ts = 'QUIT' then begin
      SQL.Clear;
      close_database;
      TextColor(12);
      System.Write('Goodbye');
      TextColor(7);
      System.Writeln('.');
      Active := False;
   end
   else if Ts = 'SAVE' then begin
      if SQL.Count=0 then {$IFDEF USE_STRINGLIST}SQL.Text:=lastSQL;{$ELSE}SQL.AddString(lastSQL);{$ENDIF}
      if SQL.Count=0 then System.Writeln('    ^ Error! You do not have any SQL in memory to save!')
      Else Begin
try
         Ts := FetchByChar(Ws, #32);
{$IFDEF USE_STRINGLIST}
         SQL.SavetoFile(Ws);
{$ELSE}
         AssignFile(TFH,Ws);
         {$I-} Rewrite(TFH); {$I+}
         SQL.First;
         Repeat
            SQL.GetString(Ts);
            Writeln(TFH,Ts);
         Until not SQL.Next;
         CloseFile(TFH);
{$ENDIF}
except
         on E:Exception do System.Writeln('    ^ Error! ',E.Message);
end;
      End;
      SQL.Clear;
   end
   else if Ts = 'LOAD' then begin
try
      Ts := FetchByChar(Ws, #32);
{$IFDEF USE_STRINGLIST}
      SQL.LoadFromFile(Ws);
{$ELSE}
      AssignFile(TFH,Ws);
      {$I-} Reset(TFH); {$I+}
      SQL.Clear;
      While not Eof(TFH) do begin
         ReadLn(TFH,Ts);
         lastSQL:=lastSQL+Ts+#13#10;
      End;
      CloseFile(TFH);
{$ENDIF}
except
      on E:Exception do System.Writeln('    ^ Error! ',E.Message);
end;
{$IFDEF USE_STRINGLIST}
      lastSQL:=SQL.Text;
      SQL.Clear;
{$ENDIF}
   end
   else if Ts = 'SET' then begin
      SQL.Clear;
      Ts:=FetchByChar(UpWs,#32);
      If Ts='TIMEOUT' then begin
         If IsNumericString(UpWs) then begin
try
            globalTimeout:=StringToInteger(UpWs);
            System.Writeln('New timeout is in place.');
except
            System.Writeln('    ^ Error! TIMEOUT value of '+UpWs+' was ingnored.');
end;
         End
         Else Begin
            System.Writeln('    ^ Error! TIMEOUT value of '+UpWs+' is supposed to be the number of milliseconds like 15000 for 15 seconds.');
         End;
      end
      else If Ts='RESULTSET' then begin
         If UpWs='CVS' then resultCode:=0
         else if UpWs='TAB' then resultCode:=1
         else if UpWs='FIXED' then resultCode:=2
         else System.Writeln('    ^ Error! Unknown RESULTSET type. See help for my information.');
      end
      else begin
         System.Writeln('    ^ Error! Unknown SET command. See help for my information.');
      end;
   end
   else if (Ts = 'HELP') or (Ts = '?') then begin
      SQL.Clear;
      System.Writeln(#13#10+'Available commands:'+#13#10+
         '  OPEN database'+#13#10+
         '  NEW database'+#13#10+
         '  CLOSE'+#13#10+
         '  QUIT'+#13#10+
         '  SQL Statements'+#13#10+
         '  SET TIMEOUT milliseconds'+#13#10+
         '  SET RESULTSET type {type=cvs,tab,fixed}'+#13#10+
         '  SAVE filename'+#13#10+
         '  LOAD filename'+#13#10+
         '  @filename {loads and executes}'+#13#10);
   end
   else begin
      if not assigned(dbhook) then begin
         System.Writeln('    ^ Error! Choices are OPEN <databasefile>, NEW <databasefile> or QUIT');
         Exit;
      end;
      if (Copy(Ts,1,1)='@') then begin
         Delete(Ws,1,1);
         if not fileexists(Ws) then begin
            System.Writeln('    ^ Error! File does not exist ',Ws);
            Exit;
         End;
try
{$IFDEF USE_STRINGLIST}
         SQL.LoadFromFile(Ws);
{$ELSE}
         AssignFile(TFH,Ws);
         {$I-} Reset(TFH); {$I+}
         SQL.Clear;
         While not Eof(TFH) do begin
            ReadLn(TFH,Ts);
            lastSQL:=lastSQL+Ts+#13#10;
         End;
         CloseFile(TFH);
         SQL.AddString(lastSQL);
{$ENDIF}
except
         on E:Exception do System.Writeln('    ^ Error! ',E.Message);
end;
      end
      else begin
         if (CharPos(';',Ws)=0) and (Ws<>'/') then begin
            {$IFDEF USE_STRINGLIST}SQL.Add(Ws){$ELSE}SQL.AddString(Ws){$ENDIF};
            Exit;
         End;
         If (SQL.Count=0) then begin
            if (Ws='/') then {$IFDEF USE_STRINGLIST}SQL.Text:=lastSQL{$ELSE}SQL.AddString(lastSQL){$ENDIF}
            Else {$IFDEF USE_STRINGLIST}SQL.Add(Ws){$ELSE}SQL.AddString(Ws){$ENDIF};
         end;
      end;
{$IFDEF USE_STRINGLIST}
      lastSQL:=SQL.Text;
{$ELSE}
      lastSQL:='';
      SQL.First;
      While SQL.Count>0 do begin
         SQL.GetString(Ts);
         If SQL.Count>1 then
            lastSQL:=lastSQL+Ts+#13#10
         Else
            lastSQL:=LastSQL+Ts;
         SQL.Delete;
      End;
{$ENDIF}
      sqlite3_busytimeout(dbhook, globalTimeout);
{$IFDEF DESIGN1}
      PMessage := SQLite3_Malloc(128);
      lineCounter:=0;
      resultCode := sqlite3_exec(dbhook, PChar(lastSQL), @sqlite3_callback, {Self} Nil, PMessage);
      SQL.Clear;
      if (resultCode > 0) then begin
         System.Writeln('    ^ Error! ',sqlite3_errmsg(dbhook));
      end
      else Begin
         sqlite3_free(PMessage);
         If lineCounter>0 then begin
            If lineCounter>1 then
               System.Writeln(#13#10+IntegerToString(lineCounter)+' Rows Displayed.'+#13#10)
            Else
               System.Writeln(#13#10+IntegerToString(lineCounter)+' Row Displayed.'+#13#10);
         End;
      End;
      PMessage := Nil;
{$ENDIF}
{$IFDEF DESIGN2}
      Ts := StringReplace(lastSQL,#13#10,#32,[rfReplaceAll]);
      SQL.Clear;
      resultCode := SQLite3_Prepare(dbhook, PChar(Ts), Length(Ts), hStmt, pZTail);

      if (resultCode > 0) then begin
         System.Writeln('    ^ Error! ',sqlite3_errmsg(dbhook));
         SQLite3_Finalize(hStmt);
         SQL.Clear;
         exit;
      end
      else Columns := SQLite3_ColumnCount(hStmt); // if zero - does not return result!
      SQLite3_Finalize(hStmt);

      PMessage := SQLite3_Malloc(128);
      resultCode := SQLite3_GetTable(dbhook, PChar(Ts), ResultSet, Rows, Columns, PMessage);

      if (resultCode > 0) then System.Writeln('    ^ Error! ',sqlite3_errmsg(dbhook))
      else if (Rows+Columns > 0) then Begin

      case resultType of
         0: begin // Comma Delimited Result set:
            PCharPos := ResultSet;
            Loop1 := 0;
            While Loop1 <= Rows do Begin
               Loop2 := 0;
               While Loop2 < Columns do Begin
                  Ts := PChar(PCharPos^);
                  If not isNumericString(Ts) then Ts:='"'+Ts+'"';
                  if Loop2 < Columns-1 then System.Write(Ts,',')
                  else System.Write(Ts);
                  Inc(Cardinal(PCharPos),4);
                  Inc(Loop2);
               End;
               Inc(Loop1);
               System.Writeln('');
            End;
         end;
         1: begin // Tab Delimited Result set:
            PCharPos := ResultSet;
            Loop1 := 0;
            While Loop1 <= Rows do Begin
               Loop2 := 0;
               While Loop2 < Columns do Begin
                  Ts := PChar(PCharPos^);
                  if Loop2 < Columns-1 then System.Write(Ts,#9)
                  else System.Write(Ts);
                  Inc(Cardinal(PCharPos),4);
                  Inc(Loop2);
               End;
               Inc(Loop1);
               System.Writeln('');
            End;
         end;
      end;
(***
//         System.Writeln('Rows ',Rows,' Columns ',Columns,' ResultSet ',Integer(ResultSet));
      For Loop1:=0 to Rows-1 do begin
         If (Loop1 mod Cardinal(pageHeight))=0 then Begin
            System.Writeln('Headers1');
            System.Writeln('Headers2');
         End;
         For Loop2:=0 to Columns-1 do begin
            Row:=@PChar(ResultSet)[Loop1];
            System.Write('Loop2=',Loop2,' @ ',PChar(Row)^,' ');
         End;
         System.Writeln('');
         If (Loop1-1 mod pageHeight)=0 then Begin
            System.Write('Press ENTER to continue.');
            System.Readln;
            System.Writeln('');
         End;
      End;
      If Rows<>1 then
         System.Writeln(#13#10+IntegerToString(Rows)+' Rows Displayed.'+#13#10)
      Else
         System.Writeln(#13#10+IntegerToString(Rows)+' Row Displayed.'+#13#10);
***)
      End;
      SQLite3_FreeTable(ResultSet);
      sqlite3_free(PMessage);
{$ENDIF}
   end;
End;

begin
// These Features are only available in new 3.6 engine:
//   SQLite3_Config(SQLITE_CONFIG_SINGLETHREAD); // because this code is single-threaded!
//   System.Writeln(SQLite3_Initialize());
//   System.Readln;
   System.Writeln(#27+'[2J'+#27+'[1;1H'+'SQL Database Engine v1.0 - '+
      'Library Version: ',sqlite3_version,#13#10+
      '(c) 2009 by Brain Patchwork DX, LLC.'+#13#10);
   SQLite3_busyhandler(dbhook, @busy_handler_func, {Self} Nil);
   dbfilename := '';
   dbhook := Nil;
   globalTimeout := 15000;
   pageHeight := 22;
   SQL := {$IFDEF USE_STRINGLIST}TStringList{$ELSE}TDXCacheArray{$ENDIF}.Create;
   resultType := 0;
   active := true;
   while (active) do begin
      doPrompt;
   end;
   SQL.Free;
end.

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// see tables: select * from sqlite_master
// see temp tables: select * from sqlite_temp_master
// Returns: type, name, tbl_name, rootpage, sql
// Type = 'table','view','index','trigger'
//
// like alter type {other way}
//        BEGIN TRANSACTION;
//        CREATE TEMPORARY TABLE t1_backup(a,b);
//        INSERT INTO t1_backup SELECT a,b FROM t1;
//        DROP TABLE t1;
//        CREATE TABLE t1(a,b);
//        INSERT INTO t1 SELECT a,b FROM t1_backup;
//        DROP TABLE t1_backup;
//        COMMIT;
//
// alter table {database.}tablename rename to newtablename;
// alter table {database.}tablename add (field and_type_size);
//
// create {temp} table {if not exists} {database.}tablename (fields and_types_sizes);
// create {temp} table {if not exists} {database.}tablename as select fields from {database.}anothertable;
//
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// BENCHMARK FROM http://www.accuracer.com/articles/single-file-delphi-database_tests100.php
// ==================================================================================================================
//                   Accuracer | EasyTable |     KeyDB |    TinyDB |   TurboDB | SQLite3 | PRAGMA |    Mac | RETINA |
// ----------------------------+-----------+-----------+-----------+-----------+---------+--------+--------+--------|
// 100,000 Inserts       9,482 |    51,749 |    85,044 |    59,789 |    73,922 |   8,352 |  8,202 |  7,725 |  1,236 |
// with Indexes         50,682 |   144,058 |   578,867 |   168,959 |   182,276 | 234,566 | 19,346 | 21,234 |  2,373 |
// 100,000 Edits         7,856 |    46,604 |    61,991 |   330,704 |    84,182 |  10,196 | 10,108 |  9,024 |  3,799 |
// with Indexes         77,711 |   205,261 | 1,315,480 | 2,365,102 |   787,736 | 547,029 | 37,828 | 29,713 |  2,983 |
// 100,000 Deletes       3,265 |   109,718 |    72,393 |    76,092 |   156,468 |   7,896 |  7,359 |  7,222 |  1,131 |
// with Indexes         34,141 |   275,515 |   945,251 |   752,031 | 1,436,655 | 171,862 | 26,903 | 21,826 |  2,339 |
// ----------------------------+-----------+-----------+-----------+-----------+---------+--------+--------+--------|
