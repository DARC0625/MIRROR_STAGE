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
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{tmp}\install-mirror-stage-ego.ps1"" -InstallRoot ""{app}"""; StatusMsg: "Installing MIRROR STAGE EGO..."; Flags: runhidden
Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Flags: postinstall nowait skipifsilent

[Icons]
Name: "{group}\Launch MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego";
Name: "{autodesktop}\MIRROR STAGE EGO"; Filename: "powershell.exe"; Parameters: "-NoExit -ExecutionPolicy Bypass -File ""{app}\ego\start_ego.ps1"""; WorkingDir: "{app}\ego"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 MIRROR STAGE EGO 바로가기 만들기"; GroupDescription: "추가 작업 선택:"; Flags: unchecked
