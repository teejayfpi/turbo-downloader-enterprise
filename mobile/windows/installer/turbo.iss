; Turbo Downloader - Windows installer (Inno Setup).
;
; Packages the release bundle into a single TurboSetup.exe that installs per
; user (no admin prompt), creates Start Menu and optional desktop shortcuts,
; registers the turbo:// handoff scheme, and supports clean uninstall.
;
; Built by .github/workflows/desktop.yml on the Windows runner. To build it by
; hand, first run `flutter build windows --release`, then compile this script
; with Inno Setup 6 (ISCC.exe).

#define AppName "Turbo Downloader"
#define AppPublisher "Olatunji Ayobami Ayanlowo"
#define AppExe "turbo_downloader.exe"
#define AppURL "https://github.com/teejayfpi/turbo-downloader-enterprise"

; Version is passed by CI (-DMyAppVersion=2.1.0); fall back for a manual build.
#ifndef MyAppVersion
  #define MyAppVersion "2.1.0"
#endif

; The release bundle, relative to this script.
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8986789C-DE00-4050-8657-753279458B3F}
AppName={#AppName}
AppVersion={#MyAppVersion}
AppVerName={#AppName} {#MyAppVersion}
AppPublisher={#AppPublisher}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=dist
OutputBaseFilename=TurboSetup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Per-user install: no admin rights required, works on a locked-down laptop.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"
Name: "quicklaunchicon"; Description: "Create a Quick Launch shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: quicklaunchicon

[Registry]
; Register the turbo:// handoff scheme so the browser extension and other
; helpers can open a link straight in Turbo.
Root: HKCU; Subkey: "Software\Classes\turbo"; ValueType: string; ValueName: ""; ValueData: "URL:Turbo Downloader"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\turbo"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\turbo\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
