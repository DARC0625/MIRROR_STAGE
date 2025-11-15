#define MyAppName "MIRROR STAGE EGO"
#define MyAppVersion "1.0"
#define MyAppPublisher "DARC0625"
#define MyAppExeName "mirror-stage-ego-setup"
#define MyOutputDir "Output"
#define MyRepoUrl "https://github.com/DARC0625/MIRROR_STAGE.git"
#define MyRepoBranch "main"

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
Source: "install-mirror-stage-ego.ps1"; DestDir: "{tmp}"; Flags: ignoreversion dontcopy
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ego\start_ego.ps1"; DestDir: "{app}\ego"; Flags: ignoreversion
Source: "..\ego\backend\*"; DestDir: "{app}\ego\backend"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "node_modules\*;dist\*;logs\*;*.log"
Source: "..\ego\frontend\*"; DestDir: "{app}\ego\frontend"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".dart_tool\*;build\*;logs\*;*.log"

[Run]
Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Flags: postinstall nowait skipifsilent

[Icons]
Name: "{group}\Launch MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"
Name: "{autodesktop}\MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 MIRROR STAGE EGO 바로가기 만들기"; GroupDescription: "추가 작업 선택:"; Flags: unchecked

[Code]
const
  WAIT_TIMEOUT = $00000102;
  WM_VSCROLL = $0115;
  SB_BOTTOM = 7;

function WaitForSingleObject(hHandle: LongWord; dwMilliseconds: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function GetExitCodeProcess(hProcess: LongWord; var lpExitCode: LongWord): LongWord;
  external 'GetExitCodeProcess@kernel32.dll stdcall';
function CloseHandle(hObject: LongWord): LongWord;
  external 'CloseHandle@kernel32.dll stdcall';
function SendMessage(hWnd: HWND; Msg, WParam, LParam: LongInt): LongInt;
  external 'SendMessageW@user32.dll stdcall';

var
  LogPage: TWizardPage;
  LogMemo: TMemo;
  ProgressLogFile: string;
  LastLogLength: Integer;
  PendingLine: string;
  ScriptExecuted: Boolean;

procedure AppendLogLine(const Line: string);
begin
  if (Line = '') or WizardSilent then
    Exit;
  LogMemo.Lines.Add(Line);
  SendMessage(LogMemo.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

procedure AppendLogChunk(const Chunk: string);
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(Chunk) do
  begin
    C := Chunk[I];
    if C = #10 then
    begin
      AppendLogLine(PendingLine);
      PendingLine := '';
    end
    else if C <> #13 then
      PendingLine := PendingLine + C;
  end;
end;

procedure PumpLog;
var
  Buffer: AnsiString;
begin
  if LoadStringFromFile(ProgressLogFile, Buffer) then
  begin
    if Length(Buffer) > LastLogLength then
    begin
      AppendLogChunk(Copy(Buffer, LastLogLength + 1, MaxInt));
      LastLogLength := Length(Buffer);
    end;
  end;
end;

procedure RunPowerShellInstaller;
var
  Cmd: string;
  ProcessHandle: LongWord;
  ExitCode: LongWord;
  WaitResult: LongWord;
begin
  if ScriptExecuted then
    Exit;
  ScriptExecuted := True;

  if FileExists(ProgressLogFile) then
    DeleteFile(ProgressLogFile);
  LastLogLength := 0;
  PendingLine := '';
  if not WizardSilent then
  begin
    LogMemo.Clear;
    WizardForm.BackButton.Enabled := False;
    WizardForm.NextButton.Enabled := False;
    WizardForm.CancelButton.Enabled := False;
  end;

  Cmd :=
    '-NoProfile -ExecutionPolicy Bypass' +
    ' -File "' + ExpandConstant('{tmp}\install-mirror-stage-ego.ps1') + '"' +
    ' -InstallRoot "' + ExpandConstant('{app}') + '"' +
    ' -RepoUrl "{#MyRepoUrl}"' +
    ' -Branch "{#MyRepoBranch}"' +
    ' -ProgressLogPath "' + ProgressLogFile + '"';

  ProcessHandle := 0;
  try
    if not Exec('powershell.exe', Cmd, '', SW_HIDE, ewNoWait, ProcessHandle) then
      RaiseException('PowerShell 설치 스크립트를 시작하지 못했습니다.');

    repeat
      WaitResult := WaitForSingleObject(ProcessHandle, 200);
      PumpLog;
      if not WizardSilent then
        WizardForm.ProcessMessages;
    until WaitResult <> WAIT_TIMEOUT;

    PumpLog;
    if PendingLine <> '' then
    begin
      AppendLogLine(PendingLine);
      PendingLine := '';
    end;
    if GetExitCodeProcess(ProcessHandle, ExitCode) = 0 then
      ExitCode := $FFFFFFFF;
    if ExitCode <> 0 then
      RaiseException('PowerShell 설치 스크립트가 실패했습니다. 로그를 확인하세요.');
  finally
    if ProcessHandle <> 0 then
      CloseHandle(ProcessHandle);
    if not WizardSilent then
    begin
      WizardForm.BackButton.Enabled := True;
      WizardForm.NextButton.Enabled := True;
      WizardForm.CancelButton.Enabled := True;
    end;
  end;
end;

procedure InitializeWizard;
begin
  ExtractTemporaryFile('install-mirror-stage-ego.ps1');
  ProgressLogFile := ExpandConstant('{tmp}\installer-progress.log');
  LastLogLength := 0;
  PendingLine := '';
  ScriptExecuted := False;

  if not WizardSilent then
  begin
    LogPage := CreateCustomPage(wpInstalling, '설치 로그', 'PowerShell 스크립트 출력');
    LogMemo := TMemo.Create(LogPage.Surface);
    LogMemo.Parent := LogPage.Surface;
    LogMemo.Left := 0;
    LogMemo.Top := 0;
    LogMemo.Width := LogPage.SurfaceWidth;
    LogMemo.Height := LogPage.SurfaceHeight;
    LogMemo.ReadOnly := True;
    LogMemo.ScrollBars := ssVertical;
    LogMemo.WordWrap := False;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (not WizardSilent) and (LogPage <> nil) and (CurPageID = LogPage.ID) and (not ScriptExecuted) then
    RunPowerShellInstaller;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if WizardSilent and (CurStep = ssInstall) and (not ScriptExecuted) then
    RunPowerShellInstaller;
end;
