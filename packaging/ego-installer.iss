#define MyAppName "MIRROR STAGE EGO"
#define MyAppVersion "1.0"
#define MyAppPublisher "DARC0625"
#define MyAppExeName "mirror-stage-ego-setup"
#define MyOutputDir "Output"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\MIRROR_STAGE
DefaultGroupName={#MyAppName}
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyAppExeName}
Compression=lzma
SolidCompression=yes

[Files]
Source: "install-mirror-stage-ego.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ego\start_ego.ps1"; DestDir: "{app}\ego"; Flags: ignoreversion
Source: "..\ego\backend\*"; DestDir: "{app}\ego\backend"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\*;dist\*;logs\*;*.log"
Source: "..\ego\frontend\*"; DestDir: "{app}\ego\frontend"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".dart_tool\*;build\*;logs\*;*.log"

[Run]
Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Flags: postinstall nowait skipifsilent; Check: InstallerCompletedSuccessfully

[Icons]
Name: "{group}\Launch MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego";
Name: "{autodesktop}\MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 MIRROR STAGE EGO 바로가기 만들기"; GroupDescription: "추가 작업 선택:"; Flags: unchecked

[Code]
const
  WAIT_OBJECT_0 = $00000000;
  WAIT_TIMEOUT = $00000102;
  WM_VSCROLL = $0115;
  SB_BOTTOM = 7;
  InstallerTotalSteps = 8;

var
  InstallerProgressPage: TOutputProgressWizardPage;
  ProgressMemo: TMemo;
  ProgressLogFile: string;
  ProgressFilePos: Integer;
  PendingLogData: AnsiString;
  InstallerSucceeded: Boolean;

function WaitForSingleObject(hHandle: LongWord; dwMilliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function GetExitCodeProcess(hProcess: LongWord; var lpExitCode: LongWord): BOOL;
  external 'GetExitCodeProcess@kernel32.dll stdcall';
function CloseHandle(hObject: LongWord): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';
function SendMessage(hWnd: HWND; Msg: UINT; wParam: Longint; lParam: Longint): Longint;
  external 'SendMessageW@user32.dll stdcall';

procedure AppendMemoLine(const S: string);
begin
  if S = '' then
    Exit;
  ProgressMemo.Lines.Add(S);
  ProgressMemo.SelStart := Length(ProgressMemo.Text);
  SendMessage(ProgressMemo.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

procedure ParseProgressPayload(const Payload: string; var Step, Total: Integer; var Msg: string);
var
  Sep1, Sep2: Integer;
  Rest: string;
begin
  Step := 0;
  Total := InstallerTotalSteps;
  Msg := Payload;
  Sep1 := Pos('|', Payload);
  if Sep1 > 0 then begin
    Step := StrToIntDef(Copy(Payload, 1, Sep1 - 1), 0);
    Rest := Copy(Payload, Sep1 + 1, Length(Payload));
    Sep2 := Pos('|', Rest);
    if Sep2 > 0 then begin
      Total := StrToIntDef(Copy(Rest, 1, Sep2 - 1), InstallerTotalSteps);
      Msg := Copy(Rest, Sep2 + 1, Length(Rest));
    end else begin
      Msg := Rest;
    end;
  end;
end;

procedure ProcessLogLine(const Line: string);
var
  Step, Total: Integer;
  Msg, Payload: string;
begin
  if Line = '' then
    Exit;
  if Copy(Line, 1, 6) = '@@LOG|' then begin
    Msg := Copy(Line, 7, Length(Line));
    AppendMemoLine(Msg);
  end else if Copy(Line, 1, 11) = '@@PROGRESS|' then begin
    Payload := Copy(Line, 12, Length(Line));
    ParseProgressPayload(Payload, Step, Total, Msg);
    if Total <= 0 then
      Total := InstallerTotalSteps;
    InstallerProgressPage.SetProgress(Step, Total);
    if Msg <> '' then
      InstallerProgressPage.SetText('Installing MIRROR STAGE EGO', Msg);
  end else if Copy(Line, 1, 9) = '@@STATUS|' then begin
    Msg := Copy(Line, 10, Length(Line));
    if Msg <> '' then
      InstallerProgressPage.SetText('Installing MIRROR STAGE EGO', Msg);
  end else begin
    AppendMemoLine(Line);
  end;
end;

procedure ProcessLogData(const Data: string; Final: Boolean);
var
  Buffer: string;
  P: Integer;
  Line: string;
begin
  Buffer := PendingLogData + Data;
  while True do begin
    P := Pos(#10, Buffer);
    if P = 0 then
      Break;
    Line := Copy(Buffer, 1, P - 1);
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    ProcessLogLine(Line);
    Delete(Buffer, 1, P);
  end;
  PendingLogData := Buffer;
  if Final and (PendingLogData <> '') then begin
    Line := PendingLogData;
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      Delete(Line, Length(Line), 1);
    ProcessLogLine(Line);
    PendingLogData := '';
  end;
end;

function UpdateProgressLog(Final: Boolean): Boolean;
var
  Content: AnsiString;
  NewContent: AnsiString;
  LenContent: Integer;
begin
  Result := False;
  if (ProgressLogFile = '') or (not FileExists(ProgressLogFile)) then
    Exit;
  if LoadStringFromFile(ProgressLogFile, Content) then begin
    LenContent := Length(Content);
    if LenContent > ProgressFilePos then begin
      NewContent := Copy(Content, ProgressFilePos + 1, LenContent - ProgressFilePos);
      ProgressFilePos := LenContent;
      ProcessLogData(NewContent, False);
      Result := True;
    end else if Final then begin
      ProcessLogData('', True);
    end;
  end;
end;

function RunInstallerScript: Boolean;
var
  Params: string;
  ProcessHandle: LongWord;
  ExitCode: LongWord;
begin
  Result := False;
  ProgressLogFile := ExpandConstant('{tmp}\ego-progress.log');
  DeleteFile(ProgressLogFile);
  ProgressFilePos := 0;
  PendingLogData := '';

  InstallerProgressPage.SetText('Installing MIRROR STAGE EGO', 'Initializing...');
  InstallerProgressPage.SetProgress(0, InstallerTotalSteps);
  InstallerProgressPage.Show;
  WizardForm.BackButton.Enabled := False;
  WizardForm.NextButton.Enabled := False;
  WizardForm.CancelButton.Enabled := False;
  WizardProcessMessages;

  Params := '-ExecutionPolicy Bypass -NoProfile -File ' +
    ExpandConstant('{tmp}\install-mirror-stage-ego.ps1') + ' -InstallRoot ' +
    ExpandConstant('{app}') + ' -ProgressLogPath ' + ProgressLogFile + '';

  if not Exec('powershell.exe', Params, '', SW_HIDE, ewNoWait, ProcessHandle) then begin
    AppendMemoLine('Failed to launch PowerShell (powershell.exe).');
    WizardForm.BackButton.Enabled := True;
    WizardForm.NextButton.Enabled := True;
    WizardForm.CancelButton.Enabled := True;
    InstallerProgressPage.Hide;
    Exit;
  end;

  try
    while True do begin
      WizardProcessMessages;
      UpdateProgressLog(False);
      if WaitForSingleObject(ProcessHandle, 150) <> WAIT_TIMEOUT then
        Break;
    end;
    UpdateProgressLog(True);
    if not GetExitCodeProcess(ProcessHandle, ExitCode) then
      ExitCode := $FFFFFFFF;
    Result := ExitCode = 0;
    if not Result then
      AppendMemoLine('PowerShell installer exited with an error. See the log for details.');
  finally
    CloseHandle(ProcessHandle);
  end;

  WizardForm.BackButton.Enabled := True;
  WizardForm.NextButton.Enabled := True;
  WizardForm.CancelButton.Enabled := True;
  InstallerProgressPage.Hide;
end;

procedure InitializeWizard;
begin
  InstallerProgressPage := CreateOutputProgressPage('Installing MIRROR STAGE EGO', 'Preparing environment...');
  ProgressMemo := TMemo.Create(InstallerProgressPage.Surface);
  ProgressMemo.Parent := InstallerProgressPage.Surface;
  ProgressMemo.Left := 0;
  ProgressMemo.Top := InstallerProgressPage.ProgressBar.Top + InstallerProgressPage.ProgressBar.Height + ScaleY(8);
  ProgressMemo.Width := InstallerProgressPage.SurfaceWidth;
  ProgressMemo.Height := InstallerProgressPage.SurfaceHeight - ProgressMemo.Top;
  ProgressMemo.Anchors := [akLeft, akTop, akRight, akBottom];
  ProgressMemo.ScrollBars := ssVertical;
  ProgressMemo.ReadOnly := True;
  ProgressMemo.WordWrap := False;
  ProgressMemo.Color := clWindow;
  ProgressMemo.Font.Name := 'Consolas';
  ProgressMemo.Font.Size := 9;

  ProgressLogFile := '';
  ProgressFilePos := 0;
  PendingLogData := '';
  InstallerSucceeded := False;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    if not RunInstallerScript then
      RaiseException('Failed to configure MIRROR STAGE EGO. Please review the installation log.');
    InstallerSucceeded := True;
  end;
end;

function InstallerCompletedSuccessfully: Boolean;
begin
  Result := InstallerSucceeded;
end;
