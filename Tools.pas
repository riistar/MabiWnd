unit Tools;

interface

uses
  Windows, SysUtils, Classes, IniFiles, StrUtils, Variants, Math, PsAPI, TlHelp32;

Type
  NTSTATUS = cardinal;
  // NTSTATUS = LongInt;
  TProcFunction = function(ProcHandle: THandle): NTSTATUS; stdcall;
  (* declare a dynamic array of Byte type *)
  xTypeByteArray = array of Byte;
  (* declare a dynamic array of PByte type *)
  xTypePtrByteArray = array of PByte;

  // Declare external functions
  function OpenThread(dwDesiredAccess: DWORD; InheritHandle: Boolean; dwThreadID: DWORD): THandle; stdcall; external 'kernel32.dll';
  procedure SwitchToThisWindow(h1: hWnd; x: bool); stdcall; external user32 Name 'SwitchToThisWindow';
  function sprintf(S: PAnsiChar; const Format: PAnsiChar): Integer; cdecl; varargs; external 'msvcrt.dll';
  function wsprintf(Output: PChar; Format: PChar): Integer; cdecl; varargs; external user32 name {$IFDEF UNICODE}'wsprintfW'{$ELSE}'wsprintfA'{$ENDIF};

  // Declare regular functions
  procedure ChangePrivilege(szPrivilege: PChar; fEnable: Boolean);  //set debug privilege on application
  function GetTthreadsList(PID: cardinal): Boolean;
  function GetThreadID(ProcessID : DWORD ) : DWORD;
  Procedure HaltThread(MainThreadID : Cardinal; Enabled: Boolean);
  function SuspendProcess(const PID: DWORD): Boolean;
  function FileVersionGet( const sgFileName : string ) : string;
  function GetModuleName: string;
  function GetFunctionAddr(Module: string; Funct : string): pointer;
  function GetModuleSize(Address: LongWord): LongWord;

  function ByteToHex(InByte:byte):shortstring;
  function PointerToByteArray(Value: Pointer; const SizeInBytes: Cardinal = 4): xTypeByteArray;

  Procedure WriteLog(Data : string; LOG : String;  Enabled: Boolean);
  function ReadCFG(const FileName: string; const Section, Key: string; const DefaultValue: Variant): Variant;

const
  STATUS_SUCCESS = $00000000;
  PROCESS_SUSPEND_RESUME = $0800;
  THREAD_SUSPEND_RESUME = $0002;
  //THREAD_SUSPEND_RESUME (0x0002)
  //THREAD_TERMINATE (0x0001)
  //THREAD_QUERY_INFORMATION (0x0040)

var
  Locale : TFormatSettings;

implementation


Procedure WriteLog(Data : string; LOG : String;  Enabled: Boolean);
var
  LogFile : TextFile;
  formattedDateTime : string;
  //LOG : String;
begin
  IF ENABLED = TRUE THEN
  Begin
    //LOG := ExtractFilePath(Tools.GetModuleName)+LOG_FILENAME;
    AssignFile(LogFile, LOG) ;

    IF FileExists(LOG) <> TRUE THEN
      Rewrite(LogFile)
    ELSE
      Append(LogFile);
      GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, Locale);
      DateTimeToString(formattedDateTime, Locale.ShortDateFormat+' hh:nnampm', now);
      WriteLn(LogFile, '['+formattedDateTime+'] '+DATA);
      CloseFile(LogFile) ;
  end;
end;

// Reads Config value based on Type
{
  Str  := ReadCFG('myconfig.ini', 'Section1', 'Key1', 'DefaultString');
  Int  := ReadCFG('myconfig.ini', 'Section2', 'Key2', 123);
  Bool := ReadCFG('myconfig.ini', 'Section3', 'Key3', True);
}
function ReadCFG(const FileName: string; const Section, Key: string; const DefaultValue: Variant): Variant;
var
  IniFile: TIniFile;
begin
  IniFile := TIniFile.Create(FileName);
  try
    case VarType(DefaultValue) of
      varInteger:
        Result := IniFile.ReadInteger(Section, Key, DefaultValue);
      varBoolean:
        Result := IniFile.ReadBool(Section, Key, DefaultValue);
    else
      Result := IniFile.ReadString(Section, Key, DefaultValue);
    end;
  finally
    IniFile.Free;
  end;
end;


function ByteToHex(InByte:byte):shortstring;
const Digits:array[0..15] of char='0123456789ABCDEF';
begin
 result:=digits[InByte shr 4]+digits[InByte and $0F];
end;

function PointerToByteArray(Value: Pointer; const SizeInBytes: Cardinal = 4): xTypeByteArray;
var Address, (* store the address locally *)
    index: integer; (* for loop *)
begin
     (* get the pointer address *)
     Address := Integer(Value);
     (* set the length of the array *)
     SetLength(Result, SizeInBytes);
     (* loop to get all bytes *)
     for index := 0 to SizeInBytes do
         (* convert the address + index to a PByte pointer,
            use the ^ operator so compiler knows that
            we refer to the pointer's value *)
         Result[index] := PByte(Ptr(Address + Index))^;
end;

procedure ChangePrivilege(szPrivilege: PChar; fEnable: Boolean);  //set debug privilege on application
var
  NewState: TTokenPrivileges;
  luid: TLargeInteger;
  hToken: THandle;
  ReturnLength: DWord;
begin
  OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES, hToken);
  LookupPrivilegeValue(nil, szPrivilege, luid);
  NewState.PrivilegeCount := 1;
  NewState.Privileges[0].Luid := luid;
  if (fEnable) then
    NewState.Privileges[0].Attributes := SE_PRIVILEGE_ENABLED
  else
    NewState.Privileges[0].Attributes := 0;
    AdjustTokenPrivileges(hToken, False, NewState, SizeOf(NewState), nil, ReturnLength);
    CloseHandle(hToken);
end;

function GetTthreadsList(PID: cardinal): Boolean;
var
  SnapProcHandle: THandle;
  NextProc: Boolean;
  TThreadEntry: TThreadEntry32;
begin
  SnapProcHandle := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  // Takes a snapshot of the all threads
  Result := (SnapProcHandle <> INVALID_HANDLE_VALUE);
  if Result then
    try
      TThreadEntry.dwSize := SizeOf(TThreadEntry);
      NextProc := Thread32First(SnapProcHandle, TThreadEntry);
      // get the first Thread
      while NextProc do
      begin

        if TThreadEntry.th32OwnerProcessID = PID then
        // Check the owner Pid against the PID requested
        begin
          Writeln('Thread ID      ' + inttohex(TThreadEntry.th32ThreadID, 8));
          Writeln('base priority  ' + inttostr(TThreadEntry.tpBasePri));
          Writeln('delta priority ' + inttostr(TThreadEntry.tpBasePri));
          Writeln('');
        end;

        NextProc := Thread32Next(SnapProcHandle, TThreadEntry);
        // get the Next Thread
      end;
    finally
      CloseHandle(SnapProcHandle); // Close the Handle
    end;
end;

function GetThreadID(ProcessID: DWORD): DWORD;
var
  Handle: THandle;
  ThreadEntry: ThreadEntry32;
  GotThread: Boolean;
begin
  Result := 0;
  Handle := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  ThreadEntry.dwSize := SizeOf(ThreadEntry);
  GotThread := Thread32First(Handle, ThreadEntry);

  if GotThread and (ThreadEntry.th32OwnerProcessID <> ProcessID) then
    repeat
      GotThread := Thread32Next(Handle, ThreadEntry);
      Result := ThreadEntry.th32ThreadID;
    until (not GotThread) or (ThreadEntry.th32OwnerProcessID = ProcessID);

end;

Procedure HaltThread(MainThreadID: cardinal; Enabled: Boolean);
var
  ThreadHandle: THandle;
begin

  ThreadHandle := OpenThread(THREAD_SUSPEND_RESUME, True, MainThreadID);

  if Enabled then
    SuspendThread(ThreadHandle)
  else
  begin
    ResumeThread(ThreadHandle);
    CloseHandle(ThreadHandle);
  end;
end;

function SuspendProcess(const PID: DWORD): Boolean;
var
  LibHandle: THandle;
  ProcHandle: THandle;
  NtSuspendProcess: TProcFunction;
begin
  Result := False;
  LibHandle := SafeLoadLibrary('ntdll.dll');
  if LibHandle <> 0 then
  try
    @NtSuspendProcess := GetProcAddress(LibHandle, 'NtSuspendProcess');
    if @NtSuspendProcess <> nil then
    begin
      ProcHandle := OpenProcess(PROCESS_SUSPEND_RESUME, False, PID);
      if ProcHandle <> 0 then
      try
        Result := NtSuspendProcess(ProcHandle) = STATUS_SUCCESS;
      finally
        CloseHandle(ProcHandle);
      end;
    end;
  finally
    FreeLibrary(LibHandle);
  end;
end;

function FileVersionGet( const sgFileName : string ) : string;
var infoSize: DWORD;
var verBuf:   pointer;
var verSize:  UINT;
var wnd:      UINT;
var FixedFileInfo : PVSFixedFileInfo;
begin
  infoSize := GetFileVersioninfoSize(PChar(sgFileName), wnd);

  result := '';

  if infoSize <> 0 then
  begin
    GetMem(verBuf, infoSize);
    try
      if GetFileVersionInfo(PChar(sgFileName), wnd, infoSize, verBuf) then
      begin
        VerQueryValue(verBuf, '\', Pointer(FixedFileInfo), verSize);

        result := IntToStr(FixedFileInfo.dwFileVersionMS div $10000) + '.' +
                  IntToStr(FixedFileInfo.dwFileVersionMS and $0FFFF) + '.' +
                  IntToStr(FixedFileInfo.dwFileVersionLS div $10000) + '.' +
                  IntToStr(FixedFileInfo.dwFileVersionLS and $0FFFF);
      end;
    finally
      FreeMem(verBuf);
    end;
  end;
end;

//========================================================================================================================
//function GetModuleName - Returns DLL/Module name
function GetModuleName: string;
var
  szFileName: array[0..MAX_PATH] of Char;
begin
  FillChar(szFileName, SizeOf(szFileName), #0);
  GetModuleFileName(hInstance, szFileName, MAX_PATH);
  Result := szFileName;
end;

//========================================================================================================================
//function GetFunctionAddr - Returns address of function from module
function GetFunctionAddr(Module: string; Funct : string): pointer;
begin
  //WriteLog(Format('[FunctionAddress] Module: %s / Funct: $s', [Module,Funct]), TRUE);
  Result := GetProcAddress(GetModuleHandle(PChar(Module)), PChar(Funct));
end;

function GetModuleSize(Address: LongWord): LongWord;
asm
  add eax, dword ptr [eax.TImageDosHeader._lfanew]
  mov eax, dword ptr [eax.TImageNtHeaders.OptionalHeader.SizeOfImage]
end;

end.
