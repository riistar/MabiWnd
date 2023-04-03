unit GameWindow;

interface

uses SysUtils, StrUtils, Classes, Windows, Messages, Winapi.MultiMon, System.IniFiles, Vcl.Dialogs, Variants, System.Generics.Collections;

 type
   GameWin = Class
     private

     public
      MabiHWND : hWnd;
      GameWindowName : String;
      WindowList: TArray<TWindowInfo>;
     published

      constructor Create; // Called when creating an instance (object) from this class
      function CheckWnd: String;
      function ResizeWindow(CurrentHWnd: HWND): Boolean;
      function ModifyWindowButtons(CurrentHWnd: HWND; EnableMaximizeButton, HideMinMaxButtons: Boolean): Boolean;
      function MakeFullscreenBorderless(CurrentHWnd: HWND): Boolean;
      function WindowMode(MabiHWND: HWND; const Value: string): Boolean;

   end;

procedure SwitchToThisWindow(hWnd: Thandle; fAltTab: boolean); stdcall; external 'User32.dll';

const
  LOG_FILENAME    = 'MabiWnd.log';
  CONFIG_FILENAME = 'MabiWnd.cfg';
  DEBUG = FALSE;

var
  CfgFile         : TIniFile;
  ThreadHandle    : THandle;
  dwThreadID      : Cardinal = 0;
  Wnd             : hWND;
  Config          : String;
  Log             : String;

  CurrentWindowIndex: Integer = -1;

implementation

uses Tools;

// Constructor : Create an instance of the class. Takes a string as argument.
// -----------------------------------------------------------------------------
constructor GameWin.Create;
begin
    //Holder Space, Just allow GameWin class to init
end;

function GameWin.CheckWnd: String;
var
  FromClass: PChar;
begin
  GetMem(FromClass, 100);
  GetClassName(GetForeGroundWindow, PChar(FromClass), 800);
  Tools.WriteLog('Wnd Class: '+StrPas(FromClass), Log, DEBUG);
  result := StrPas(FromClass);
  FreeMem(FromClass);
end;

function GameWin.ResizeWindow(CurrentHWnd: HWND): Boolean;
var
  DesktopRect, WindowRect: TRect;
begin
  Result := False;
  // Get the coordinates of the desktop area excluding the taskbar
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @DesktopRect, 0) then
  begin
    // Get the current size and position of the window
    if GetWindowRect(CurrentHWnd, WindowRect) then
    begin
      // Calculate the new size and position of the window
      WindowRect.Right := WindowRect.Left + (DesktopRect.Right - DesktopRect.Left);
      WindowRect.Bottom := WindowRect.Top + (DesktopRect.Bottom - DesktopRect.Top);
      // Set the size and position of the window
      if SetWindowPos(CurrentHWnd, 0, WindowRect.Left, WindowRect.Top,
        WindowRect.Right - WindowRect.Left, WindowRect.Bottom - WindowRect.Top,
        SWP_NOZORDER or SWP_NOACTIVATE) then
        Result := True;
    end;
  end;
end;

function GameWin.ModifyWindowButtons(CurrentHWnd: HWND; EnableMaximizeButton, HideMinMaxButtons: Boolean): Boolean;
const
  WS_MINIMIZEBOX = $00020000;
  WS_MAXIMIZEBOX = $00010000;
var
  WindowStyle: NativeInt;
begin
  Result := False;
  // Get the current window style
  WindowStyle := GetWindowLongPtr(CurrentHWnd, GWL_STYLE);
  if WindowStyle = 0 then
    Exit;

  // Modify the window style based on the input parameters
  if EnableMaximizeButton then
    WindowStyle := WindowStyle or WS_MAXIMIZEBOX
  else
    WindowStyle := WindowStyle and not WS_MAXIMIZEBOX;

  if HideMinMaxButtons then
  begin
    WindowStyle := WindowStyle and not WS_MINIMIZEBOX;
    WindowStyle := WindowStyle and not WS_MAXIMIZEBOX;
  end;

  // Set the new window style
  if SetWindowLongPtr(CurrentHWnd, GWL_STYLE, WindowStyle) <> 0 then
    Result := True;
end;

function GameWin.MakeFullscreenBorderless(CurrentHWnd: HWND): Boolean;
const
  WS_POPUP = $80000000;
  WS_VISIBLE = $10000000;
  WS_SYSMENU = $00080000;
  WS_THICKFRAME = $00040000;
  WS_CAPTION = WS_BORDER or WS_DLGFRAME or WS_THICKFRAME;
  SWP_FRAMECHANGED = $0020;
var
  Style, ExStyle: NativeInt;
  Monitor: HMONITOR;
  MonitorInfo: TMonitorInfo;
  Left, Top, Width, Height: Integer;
begin
  // Get the current monitor
  Monitor := MonitorFromWindow(CurrentHWnd, MONITOR_DEFAULTTONEAREST);
  MonitorInfo.cbSize := SizeOf(MonitorInfo);
  GetMonitorInfo(Monitor, @MonitorInfo);
  // Set the new window style
  Style := GetWindowLongPtr(CurrentHWnd, GWL_STYLE);
  ExStyle := GetWindowLongPtr(CurrentHWnd, GWL_EXSTYLE);
  SetWindowLongPtr(CurrentHWnd, GWL_STYLE, WS_POPUP or WS_VISIBLE);
  SetWindowLongPtr(CurrentHWnd, GWL_EXSTYLE, WS_EX_APPWINDOW or WS_EX_WINDOWEDGE);
  // Set the new window position and size
  Left := MonitorInfo.rcMonitor.Left;
  Top := MonitorInfo.rcMonitor.Top;
  Width := MonitorInfo.rcMonitor.Right - MonitorInfo.rcMonitor.Left;
  Height := MonitorInfo.rcMonitor.Bottom - MonitorInfo.rcMonitor.Top;
  SetWindowPos(CurrentHWnd, HWND_TOPMOST, Left, Top, Width, Height, SWP_FRAMECHANGED);
  // Update the window
  UpdateWindow(CurrentHWnd);
  Result := True;
end;

function GameWin.WindowMode(MabiHWND: HWND; const Value: string): Boolean;
begin
  case AnsiIndexText(Value, ['EnableMxBTN', 'AutoMx', 'BorderlessFS']) of
    0: begin
          SwitchToThisWindow(MabiHWND, True);
          ModifyWindowButtons(MabiHWND, TRUE, FALSE);
          Tools.WriteLog('Window Mode set to: EnableMxBTN', Log, TRUE);
          Tools.WriteLog('Enabled maximize button', Log, TRUE);
          result := TRUE;
       end;
    1: begin
          SwitchToThisWindow(MabiHWND, True);
          ModifyWindowButtons(MabiHWND, TRUE, FALSE);
          ShowWindow(MabiHWND, SW_MAXIMIZE);
          Tools.WriteLog('Window Mode set to: AutoMx', Log, TRUE);
          Tools.WriteLog('Enabled maximize button and Maximized window!', Log, TRUE);
          result := TRUE;
       end;
    2: begin
          SwitchToThisWindow(MabiHWND, True);
          MakeFullscreenBorderless(MabiHWND);
          Tools.WriteLog('Window Mode set to: BorderlessFS', Log, TRUE);
          Tools.WriteLog('Window maximized to Full Screen Boarderless!', Log, TRUE);
          result := TRUE;
       end;
    else
    begin
      Tools.WriteLog('Window Mode invalid, check cfg!', Log, TRUE);
      Tools.WriteLog('Ending thread...', Log, TRUE);
      EndThread(0);
      result := FALSE;
    end;
  end;
end;

//==========================================================================================================================

procedure FindWHND;
var
  WinModeEx : Boolean;
  MabiWnd: GameWin;
begin

  Tools.WriteLog('Find window thread created...', Log, TRUE);
  Tools.WriteLog('Window Mode: '+Tools.ReadCFG(Config,'MabiWindow','Mode', 'None'), Log, TRUE);

  WinModeEx := FALSE;

  Try
    MabiWnd := GameWin.Create;
  Except
    on E : Exception do
     Tools.WriteLog(E.ClassName+' error raised, with message : '+E.Message, Log, TRUE);
  End;

  try
    Repeat
      if MabiWnd.CheckWnd = 'Mabinogi' then
      begin
        Tools.WriteLog('Mabinogi window found, changing window mode...', Log, TRUE);
        WinModeEx := MabiWnd.WindowMode(GetForeGroundWindow,Tools.ReadCFG(Config,'MabiWindow','Mode', 'None'));
      end;
    until WinModeEx = TRUE;
  Except
    on E : Exception do
      Tools.WriteLog(E.ClassName+' error raised, with message : '+E.Message, Log, TRUE);
  End;

    Tools.WriteLog('Ending thread...', Log, TRUE);
    EndThread(0);

end;

// ========================================================================================================================
// All code below is excuted when this module is loaded according to compile order
initialization

  Config  := ExtractFilePath(Tools.GetModuleName)+CONFIG_FILENAME;
  Log     := ExtractFilePath(Tools.GetModuleName)+LOG_FILENAME;

  if ReadCFG(Config,'MabiWindow','Enabled', FALSE) then
  begin
    DeleteFile(PWideChar(Log));
    ThreadHandle := CreateThread(nil, 0, @FindWHND, nil, 0, dwThreadID);
  end;

// ========================================================================================================================
// All code below is excuted when this module is unloaded according to compile order
finalization

  EndThread(ThreadHandle);

end.


{
function GameWin.EnableMxButton(CurrentHWnd: HWND; Enable: Boolean): Boolean;
const
  WS_MAXIMIZEBOX = $00010000;
var
  WindowStyle: NativeInt;
begin
  Result := False;
  // Get the current window style
  WindowStyle := GetWindowLongPtr(CurrentHWnd, GWL_STYLE);
  if WindowStyle = 0 then
    Exit;
  // Enable or disable the maximize button by adding or removing the WS_MAXIMIZEBOX style flag
  if Enable then
    WindowStyle := WindowStyle or WS_MAXIMIZEBOX
  else
    WindowStyle := WindowStyle and not WS_MAXIMIZEBOX;
  // Set the new window style
  if SetWindowLongPtr(CurrentHWnd, GWL_STYLE, WindowStyle) <> 0 then
    Result := True;
end;

function GameWin.HideMinMaxButtons(CurrentHWnd: HWND): Boolean;
const
  WS_MINIMIZEBOX = $00020000;
  WS_MAXIMIZEBOX = $00010000;
var
  Style: DWORD;
begin
  // Get the current window style
  Style := GetWindowLong(CurrentHWnd, GWL_STYLE);
  if Style = 0 then
  begin
    Result := False;
    Exit;
  end;
  // Remove the minimize and maximize buttons from the style
  Style := Style and not WS_MINIMIZEBOX;
  Style := Style and not WS_MAXIMIZEBOX;
  // Set the new window style
  Result := SetWindowLong(CurrentHWnd, GWL_STYLE, Style) <> 0;
end;
}
