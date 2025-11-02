#define MyAppName "MIRROR STAGE EGO"
#define MyAppVersion "1.0"
#define MyAppPublisher "DARC0625"
#define MyAppExeName "mirror-stage-ego-setup"
#define MyOutputDir "Output"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={pf}\MIRROR_STAGE
DefaultGroupName={#MyAppName}
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyAppExeName}
Compression=lzma
SolidCompression=yes

[Files]
Source: "install-mirror-stage-ego.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{tmp}\install-mirror-stage-ego.ps1"" -InstallRoot ""{app}"""; StatusMsg: "Installing MIRROR STAGE EGO..."; Flags: runhidden

[Icons]
Name: "{group}\Start EGO Backend"; Filename: "cmd.exe"; Parameters: "/K ""cd /d {app}\MIRROR_STAGE\ego\backend && npm run start:dev""";
Name: "{group}\Start EGO Frontend"; Filename: "cmd.exe"; Parameters: "/K ""cd /d {app}\MIRROR_STAGE\ego\frontend && flutter run -d edge --web-hostname=0.0.0.0 --web-port=8080 --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin""";
