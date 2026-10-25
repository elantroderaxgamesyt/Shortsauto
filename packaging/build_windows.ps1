# Construye la carpeta portable de ShortsAuto para Windows y, si hay Inno Setup, el instalador.
# Uso (PowerShell):  powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist\ShortsAuto"
$Cache = Join-Path $Root "build\cache"
$PyVersion = "3.11.9"

New-Item -ItemType Directory -Force -Path $Dist, $Cache | Out-Null

function Get-File($url, $out) {
    if (-not (Test-Path $out)) {
        Write-Host "Descargando $url"
        Invoke-WebRequest -Uri $url -OutFile $out
    }
}

# 1. Python embebido + pip
$PyZip = Join-Path $Cache "python-$PyVersion-embed-amd64.zip"
Get-File "https://www.python.org/ftp/python/$PyVersion/python-$PyVersion-embed-amd64.zip" $PyZip
$Py = Join-Path $Dist "python"
if (-not (Test-Path "$Py\python.exe")) {
    Expand-Archive $PyZip -DestinationPath $Py
    # Activa site-packages en el Python embebido.
    $pth = Get-ChildItem "$Py\python*._pth" | Select-Object -First 1
    (Get-Content $pth) -replace "^#\s*import site", "import site" | Set-Content $pth
    $GetPip = Join-Path $Cache "get-pip.py"
    Get-File "https://bootstrap.pypa.io/get-pip.py" $GetPip
    & "$Py\python.exe" $GetPip --no-warn-script-location
}
& "$Py\python.exe" -m pip install --no-warn-script-location -r (Join-Path $Root "requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "pip install falló" }

# 2. FFmpeg (build GPL de gyan.dev: incluye libass, x264 y NVENC)
$FfZip = Join-Path $Cache "ffmpeg-release-essentials.zip"
Get-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $FfZip
$Bin = Join-Path $Dist "bin"
New-Item -ItemType Directory -Force -Path $Bin | Out-Null
if (-not (Test-Path "$Bin\ffmpeg.exe")) {
    $tmp = Join-Path $Cache "ffmpeg"
    Expand-Archive $FfZip -DestinationPath $tmp -Force
    Copy-Item (Get-ChildItem $tmp -Recurse -Filter ffmpeg.exe | Select-Object -First 1).FullName $Bin
    Copy-Item (Get-ChildItem $tmp -Recurse -Filter LICENSE | Select-Object -First 1).FullName "$Bin\FFMPEG-LICENSE.txt"
}
# llama-server necesita el runtime de Visual C++; el Python embebido ya lo trae.
New-Item -ItemType Directory -Force -Path "$Bin\llama" | Out-Null
Copy-Item "$Py\vcruntime140*.dll" "$Bin\llama\" -Force

# 3. Código de la aplicación
foreach ($item in "main.py", "config.yaml", "README.md", "LICENSES.md", "src", "assets", "ejemplos") {
    Copy-Item (Join-Path $Root $item) $Dist -Recurse -Force
}
Get-ChildItem $Dist -Recurse -Directory -Filter __pycache__ | Remove-Item -Recurse -Force

# 4. Lanzadores
Set-Content "$Dist\ShortsAuto.vbs" 'CreateObject("WScript.Shell").Run """" & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\python\pythonw.exe"" """ & CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\main.py""", 0'
Set-Content "$Dist\ShortsAuto-consola.bat" "@echo off`r`ncd /d %~dp0`r`npython\python.exe main.py %*`r`npause"

# 5. Instalador (opcional)
$Iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($Iscc) {
    & $Iscc (Join-Path $PSScriptRoot "ShortsAuto.iss")
    Write-Host "Instalador creado en dist\"
} else {
    Write-Host "Inno Setup no encontrado: queda la versión portable en dist\ShortsAuto"
}
