[Setup]
; Identificador unico para la aplicacion
AppId={{5D53DF73-B5DF-4A17-8BEE-C68C9F8A8893}
AppName=Sonero
AppVersion=1.0.0
AppPublisher=Sonero Inc.
DefaultDirName={localappdata}\Sonero
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
; Carpeta donde se guardara el "Setup.exe" final
OutputDir=C:\Users\hbriceno\Desktop\sonero\sonero-app\installers
OutputBaseFilename=Sonero_Setup
SetupIconFile=C:\Users\hbriceno\Desktop\sonero\sonero-app\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Toda la carpeta Release (Flutter app + DLLs + data + backend)
Source: "C:\Users\hbriceno\Desktop\sonero\sonero-app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Sonero"; Filename: "{app}\sonero_app.exe"
Name: "{autodesktop}\Sonero"; Filename: "{app}\sonero_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sonero_app.exe"; Description: "{cm:LaunchProgram,Sonero}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Matar el backend al desinstalar
Filename: "taskkill"; Parameters: "/F /IM sonero_backend.exe"; Flags: runhidden; RunOnceId: "KillBackend"
