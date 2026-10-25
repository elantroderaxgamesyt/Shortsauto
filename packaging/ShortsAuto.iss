; Instalador de ShortsAuto (Inno Setup 6)
#define AppVersion GetEnv("SHORTSAUTO_VERSION")
#if AppVersion == ""
  #define AppVersion "0.1.0"
#endif

[Setup]
AppId={{6C2B7C0E-9A55-4E7B-9C1B-5B0D4F1E7A21}
AppName=ShortsAuto
AppVersion={#AppVersion}
AppPublisher=ShortsAuto
; Por usuario: los modelos se descargan dentro de la carpeta de la app sin pedir permisos.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\ShortsAuto
DefaultGroupName=ShortsAuto
OutputDir=..\dist
OutputBaseFilename=ShortsAuto-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
WizardStyle=modern

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "..\dist\ShortsAuto\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\ShortsAuto"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\main.py"""; WorkingDir: "{app}"
Name: "{userdesktop}\ShortsAuto"; Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\main.py"""; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"

[Run]
Filename: "{app}\python\pythonw.exe"; Parameters: """{app}\main.py"""; WorkingDir: "{app}"; Description: "Abrir ShortsAuto"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\models"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\bin\llama"
