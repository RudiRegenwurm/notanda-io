<#
    notanda-setup.ps1 - Stufe 2 des Installationswegs
    Open-Access Harvester / Notanda, Version 1.3.0, Windows

    Was dieses Skript tut, in einem Satz:
    Es fuehrt genau die Schritte 1 bis 9 der Windows-Anleitung aus und sagt nach
    jedem Schritt in Klartext, ob er geklappt hat.

    Was es NICHT tut:
    Es braucht keine Administratorrechte. Es schreibt nichts in "Program Files",
    nichts in die Registry und nichts ausserhalb Deines Benutzerordners. Es
    veraendert keine systemweite Einstellung. Du kannst es vorher lesen.

    Aufruf (eine Zeile, in PowerShell einfuegen):
      powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\notanda-setup.ps1"

    Nur einrichten, noch nicht starten:
      powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Downloads\notanda-setup.ps1" -SetupOnly

    Am Ende liegt ein vollstaendiges Protokoll in
      %USERPROFILE%\OA-Harvester-BetaTest-1.3.0\setup-log.txt
    und ein maschinenlesbarer Bericht in
      %USERPROFILE%\OA-Harvester-BetaTest-1.3.0\setup-report.json
    Diese beiden Dateien ersetzen die Screenshots.
#>

[CmdletBinding()]
param(
    [switch] $SetupOnly,
    [switch] $Preview,
    [string] $ContactEmail,
    [string] $PythonExe,
    [string] $WheelPath,
    [string] $TestRoot,
    [int]    $Port = 8765
)

# ---------------------------------------------------------------------------
# Feste Werte des Release 1.3.0. Quelle: docs/operations.md, Build- und
# Verifikationsprotokoll vom 16.09.2026.
# ---------------------------------------------------------------------------
$WheelName    = 'oa_harvester-1.3.0-py3-none-any.whl'
$WheelBytes   = 403721
$WheelSha256  = '7d655584e4205bdd3deae5c8d7be01732a09c7ff8a24e90c1c89dd8fd404dd74'
$PythonTag    = '3.11'
$ExpectedVer  = 'harvester 1.3.0'

# -Preview ist ausser Kraft. Der Vorschaubuild 1.2.1+notandaui.e8e23d6 stammt aus
# dem Stand VOR dem Layoutfix 4f49fa6 und traegt den Fehler am Knopf
# "Start harvest" noch. Release 1.3.0 enthaelt dieselbe Oberflaeche mit dem Fix.
if ($Preview) {
    Write-Host 'Der Schalter -Preview wird nicht mehr unterstuetzt.' -ForegroundColor Red
    Write-Host 'Der Vorschaubuild ist durch Release 1.3.0 abgeloest. Bitte ohne -Preview starten.' -ForegroundColor Yellow
    exit 1
}

# Zielordner. Standard ist der Ordner der Anleitung; mit -TestRoot laesst sich
# ein anderer waehlen, etwa um einen vorhandenen Nachweis nicht anzufassen.
if (-not $TestRoot) {
    $TestRoot = Join-Path $env:USERPROFILE 'OA-Harvester-BetaTest-1.3.0'
}
$Venv     = Join-Path $TestRoot '.venv'
$Work     = Join-Path $TestRoot 'work'
$LogFile  = Join-Path $TestRoot 'setup-log.txt'
$RepFile  = Join-Path $TestRoot 'setup-report.json'

$Script:Steps = @()

# ---------------------------------------------------------------------------
# Ausgabe. Jeder Schritt meldet sein Ergebnis selbst in Klartext.
# Kein Schritt laesst den Benutzer raten, ob leere Ausgabe gut oder schlecht ist.
# ---------------------------------------------------------------------------
function Write-Step {
    param([string] $Text)
    Write-Host ''
    Write-Host ('=== ' + $Text + ' ') -ForegroundColor Cyan
}

function Add-Result {
    param([string] $Name, [string] $State, [string] $Detail)
    $Script:Steps += [pscustomobject]@{ step = $Name; state = $State; detail = $Detail }
}

function Write-Ok {
    param([string] $Name, [string] $Detail)
    Write-Host ('OK: ' + $Detail) -ForegroundColor Green
    Add-Result -Name $Name -State 'ok' -Detail $Detail
}

function Write-Info {
    param([string] $Text)
    Write-Host ('   ' + $Text) -ForegroundColor Gray
}

function Stop-Setup {
    param([string] $Name, [string] $Detail, [string] $WhatToDo)
    Write-Host ''
    Write-Host ('STOPP: ' + $Detail) -ForegroundColor Red
    if ($WhatToDo) {
        Write-Host ''
        Write-Host 'Was jetzt zu tun ist:' -ForegroundColor Yellow
        Write-Host $WhatToDo -ForegroundColor Yellow
    }
    Add-Result -Name $Name -State 'stop' -Detail $Detail
    Save-Report
    Write-Host ''
    Write-Host ('Protokoll: ' + $LogFile)
    Write-Host ('Bericht:   ' + $RepFile)
    Write-Host 'Bitte diese beiden Dateien schicken. Nichts weiter versuchen.' -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

function Save-Report {
    $report = [pscustomobject]@{
        generated   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        script      = 'notanda-setup.ps1'
        target      = '1.3.0'
        computer    = $env:COMPUTERNAME
        user        = $env:USERNAME
        os          = [string](Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        psversion   = $PSVersionTable.PSVersion.ToString()
        testroot    = $TestRoot
        steps       = $Script:Steps
    }
    try {
        $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RepFile -Encoding UTF8
    } catch {
        Write-Host ('Hinweis: Bericht konnte nicht geschrieben werden: ' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Work | Out-Null
try { Start-Transcript -LiteralPath $LogFile -Force | Out-Null } catch { }

Write-Host ''
Write-Host 'Notanda / OA-Harvester 1.3.0 - Einrichtung fuer den Windows-Test' -ForegroundColor White
Write-Host '----------------------------------------------------------------'
Write-Info ('Zielordner: ' + $TestRoot)
Write-Info  'Es werden keine Administratorrechte gebraucht.'
Write-Info  'Abbrechen ist jederzeit mit Strg+C moeglich.'

# --- 0. Nicht als Administrator ---------------------------------------------
Write-Step '0. Rechte pruefen'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-Setup -Name 'rights' -Detail 'Diese PowerShell laeuft als Administrator.' `
        -WhatToDo 'Fenster schliessen, PowerShell normal oeffnen (nicht "Als Administrator ausfuehren") und das Skript erneut starten.'
}
Write-Ok -Name 'rights' -Detail 'PowerShell laeuft mit normalen Benutzerrechten.'

# --- 1. Python --------------------------------------------------------------
# Standardweg ist der Launcher mit der festgelegten Version. Mit -PythonExe laesst
# sich ein bereits vorhandener Interpreter ausdruecklich vorgeben; das Produkt
# verlangt laut pyproject.toml nur >= 3.10.
$PyExe  = 'py'
$PyArgs = @("-$PythonTag")

if ($PythonExe) {
    Write-Step '1. Python pruefen (ausdruecklich vorgegebener Pfad)'
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        Stop-Setup -Name 'python' -Detail ('Der angegebene Python-Pfad existiert nicht: ' + $PythonExe) `
            -WhatToDo 'Pfad pruefen und das Skript erneut starten, oder -PythonExe weglassen.'
    }
    $PyExe = $PythonExe; $PyArgs = @()
    $pyVersion = & $PyExe --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup -Name 'python' -Detail ('Der angegebene Interpreter laesst sich nicht ausfuehren: ' + $PythonExe) `
            -WhatToDo 'Protokoll schicken.'
    }
    Write-Info 'Abweichend von der Standardvorgabe 3.11, weil ausdruecklich angegeben.'
    Write-Ok -Name 'python' -Detail ('Verwendet: ' + ([string]$pyVersion).Trim() + ' aus ' + $PythonExe)
    $SkipLauncherCheck = $true
} else {
    $SkipLauncherCheck = $false
}

if (-not $SkipLauncherCheck) {
Write-Step '1. Python 3.11 pruefen'
$pyCmd = Get-Command py -ErrorAction SilentlyContinue
if (-not $pyCmd) {
    Stop-Setup -Name 'python' -Detail 'Der Python-Starter "py" ist auf diesem Rechner nicht vorhanden.' `
        -WhatToDo @'
1. Im Browser oeffnen: https://www.python.org/downloads/release/python-3119/
2. Im Kasten "Windows" den Knopf "Download Python install manager" nehmen.
3. Die heruntergeladene Datei starten und alle Fragen mit y beantworten.
4. PowerShell schliessen, neu oeffnen, dieses Skript erneut starten.
'@
}

$pyVersion = & py "-$PythonTag" --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Info ('Python ' + $PythonTag + ' ist noch nicht installiert. Versuche Nachinstallation ...')
    & py install $PythonTag 2>&1 | ForEach-Object { Write-Info $_ }
    $pyVersion = & py "-$PythonTag" --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Zwei verschiedene Ursachen, zwei verschiedene Auswege. Der alte
        # "Python Launcher" kennt kein "py install"; er sagt das selbst.
        $vorhandene = (& py -0p 2>&1 | Out-String).Trim()
        $legacy = ($vorhandene -match 'legacy') -or ((& py install 3.11 2>&1 | Out-String) -match 'legacy py.exe')
        $hinweis = @'
Zwei Wege, der erste ist schneller:

A) Einen bereits vorhandenen Python-Interpreter verwenden (ab 3.10 genuegt).
   Vorhandene Installationen anzeigen:
     py -0p
   Dann dieses Skript erneut starten und den Pfad mitgeben, zum Beispiel:
     ... notanda-setup.ps1 -PythonExe "C:\Pfad\zu\python.exe"

B) Python 3.11 nachinstallieren:
   1. Im Browser oeffnen: https://www.python.org/downloads/release/python-3119/
   2. Unter "Files" die Zeile "Windows installer (64-bit)" anklicken.
   3. Die .exe starten, unten "Add python.exe to PATH" aktivieren, dann "Install Now"
      fuer das eigene Benutzerkonto (nicht fuer alle Benutzer).
   4. PowerShell schliessen, neu oeffnen, dieses Skript erneut starten.
'@
        if ($legacy) {
            Write-Info 'Befund: Auf diesem Rechner laeuft der ALTE Python Launcher.'
            Write-Info 'Der kennt den Befehl "py install" nicht - deshalb die Fehlermeldung oben.'
        }
        if ($vorhandene) { Write-Info ('Gefundene Installationen: ' + ($vorhandene -replace "`r?`n", ' | ')) }
        Stop-Setup -Name 'python' -Detail ('Python ' + $PythonTag + ' konnte nicht bereitgestellt werden.') `
            -WhatToDo $hinweis
    }
    Write-Info ('Nachinstallation erfolgreich.')
}
Write-Ok -Name 'python' -Detail ('Gefunden: ' + ([string]$pyVersion).Trim())
}

# --- 2. Wheel finden --------------------------------------------------------
Write-Step '2. Installationsdatei pruefen'
if (-not $WheelPath) {
    $WheelPath = Join-Path $env:USERPROFILE (Join-Path 'Downloads' $WheelName)
}
if (-not (Test-Path -LiteralPath $WheelPath)) {
    Stop-Setup -Name 'wheel' -Detail ('Datei nicht gefunden: ' + $WheelPath) `
        -WhatToDo ('Die Datei ' + $WheelName + ' in den Ordner "Downloads" laden und das Skript erneut starten. Der Dateiname muss exakt stimmen; eine aeltere 1.2.1-Datei genuegt nicht.')
}

$wheelItem = Get-Item -LiteralPath $WheelPath
$actualSha = (Get-FileHash -LiteralPath $WheelPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Info ('Datei:    ' + $wheelItem.Name)
Write-Info ('Groesse:  ' + $wheelItem.Length + ' Byte (erwartet ' + $WheelBytes + ')')
Write-Info ('SHA-256:  ' + $actualSha)

if ($wheelItem.Length -ne $WheelBytes -or $actualSha -ne $WheelSha256) {
    Stop-Setup -Name 'wheel' -Detail 'Groesse oder Pruefsumme stimmen nicht mit dem Release 1.3.0 ueberein.' `
        -WhatToDo 'Die Datei nicht verwenden. Erneut herunterladen und das Skript noch einmal starten. Bleibt es dabei: Protokoll schicken.'
}
Write-Ok -Name 'wheel' -Detail 'Datei und Pruefsumme stimmen mit Release 1.3.0 ueberein.'

# --- 3. Umgebung ------------------------------------------------------------
Write-Step '3. Isolierte Umgebung anlegen'
$venvPython = Join-Path $Venv 'Scripts\python.exe'
if (Test-Path -LiteralPath $venvPython) {
    Write-Info 'Eine Umgebung ist bereits vorhanden und wird weiterverwendet.'
} else {
    & $PyExe @PyArgs -m venv $Venv 2>&1 | ForEach-Object { Write-Info $_ }
    if (-not (Test-Path -LiteralPath $venvPython)) {
        Stop-Setup -Name 'venv' -Detail 'Die isolierte Umgebung konnte nicht angelegt werden.' `
            -WhatToDo 'Protokoll schicken. Haeufigste Ursache: der Ordner ist von einem anderen Programm belegt.'
    }
}
Write-Ok -Name 'venv' -Detail ('Umgebung bereit: ' + $Venv)

# --- 4. Installieren --------------------------------------------------------
Write-Step '4. Programm installieren'
Write-Info 'Das kann ein bis zwei Minuten dauern und braucht Internet.'
& $venvPython -m pip install --upgrade pip 2>&1 | ForEach-Object { Write-Info $_ }
& $venvPython -m pip install $WheelPath 2>&1 | ForEach-Object { Write-Info $_ }
if ($LASTEXITCODE -ne 0) {
    Stop-Setup -Name 'install' -Detail 'Die Installation ist fehlgeschlagen.' `
        -WhatToDo 'Protokoll schicken. Haeufigste Ursachen: keine Internetverbindung oder ein Proxy im Weg.'
}

$harvesterExe = Join-Path $Venv 'Scripts\harvester.exe'
if (-not (Test-Path -LiteralPath $harvesterExe)) {
    Stop-Setup -Name 'install' -Detail 'Nach der Installation fehlt das Programm harvester.exe.' `
        -WhatToDo 'Protokoll schicken.'
}
Write-Ok -Name 'install' -Detail 'Installation abgeschlossen.'

# --- 5. Installation pruefen ------------------------------------------------
Write-Step '5. Installation pruefen'
$verOut = (& $harvesterExe --version 2>&1 | Out-String).Trim()
Write-Info ('Version:     ' + $verOut)
if ($verOut -notmatch [regex]::Escape($ExpectedVer)) {
    Stop-Setup -Name 'verify' -Detail ('Erwartet wurde "' + $ExpectedVer + '", gemeldet wird "' + $verOut + '".') `
        -WhatToDo 'Protokoll schicken. Vermutlich liegt noch eine aeltere Version im Ordner.'
}

$impOut = (& $venvPython -c "import harvester; print(harvester.__file__)" 2>&1 | Out-String).Trim()
Write-Info ('Importpfad:  ' + $impOut)
if ($impOut -notlike (Join-Path $Venv '*')) {
    Stop-Setup -Name 'verify' -Detail 'Das Programm wird von ausserhalb der isolierten Umgebung geladen.' `
        -WhatToDo 'Protokoll schicken.'
}

$statusOut = (& $harvesterExe status --state-db (Join-Path $Work 'state.sqlite3') --storage-root (Join-Path $Work 'corpus') --reports-dir (Join-Path $Work 'reports') 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    Stop-Setup -Name 'verify' -Detail 'Die Statusabfrage ist fehlgeschlagen.' -WhatToDo 'Protokoll schicken.'
}
$statusOut.TrimEnd().Split("`n") | ForEach-Object { Write-Info $_.TrimEnd() }
Write-Ok -Name 'verify' -Detail ($verOut + ', Importpfad in der isolierten Umgebung, Statusabfrage fehlerfrei.')

# --- 6. Port ----------------------------------------------------------------
Write-Step ('6. Port ' + $Port + ' pruefen')
$busy = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Stop-Setup -Name 'port' -Detail ('Port ' + $Port + ' wird bereits von einem anderen Programm benutzt.') `
        -WhatToDo ('Das Skript mit einem anderen Port starten, zum Beispiel:' + [Environment]::NewLine + '  powershell -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Port 8766')
}
Write-Ok -Name 'port' -Detail ('Port ' + $Port + ' ist frei.')

# --- 7. Zugangsdaten --------------------------------------------------------
Write-Step '7. Zugangsdaten'
if (-not $env:HARVESTER_OPENALEX_API_KEY) {
    Write-Info 'Beim Tippen oder Einfuegen erscheinen nur Sternchen. Das ist richtig so.'
    Write-Info 'Der Schluessel wird nur in diesem Fenster gesetzt, nirgends gespeichert'
    Write-Info 'und steht in keinem Protokoll.'
    Write-Info 'Wo Du ihn bekommst: openalex.org/settings/api, Schaltflaeche "Copy".'
    $secure = Read-Host -Prompt 'OpenAlex-Schluessel' -AsSecureString
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $env:HARVESTER_OPENALEX_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
if (-not $env:HARVESTER_OPENALEX_API_KEY) {
    Stop-Setup -Name 'credentials' -Detail 'Es wurde kein OpenAlex-Schluessel eingegeben.' `
        -WhatToDo 'Schluessel auf openalex.org/settings/api holen und das Skript erneut starten.'
}

if (-not $ContactEmail) { $ContactEmail = $env:HARVESTER_CONTACT_EMAIL }
if (-not $ContactEmail) { $ContactEmail = Read-Host -Prompt 'Kontakt-E-Mail-Adresse (fuer Unpaywall)' }
if (-not $ContactEmail) {
    Stop-Setup -Name 'credentials' -Detail 'Es wurde keine Kontaktadresse eingegeben.' `
        -WhatToDo 'Das Skript erneut starten und eine E-Mail-Adresse angeben.'
}
$env:HARVESTER_CONTACT_EMAIL = $ContactEmail
Write-Ok -Name 'credentials' -Detail ('Schluessel gesetzt (nicht protokolliert), Kontaktadresse ' + $ContactEmail + '.')

Save-Report

# --- 8. Start ---------------------------------------------------------------
Write-Step '8. Starten'
$startArgs = @(
    'serve',
    '--host', '127.0.0.1',
    '--port', "$Port",
    '--state-db',     (Join-Path $Work 'state.sqlite3'),
    '--storage-root', (Join-Path $Work 'corpus'),
    '--reports-dir',  (Join-Path $Work 'reports')
)

if ($SetupOnly) {
    Write-Host ''
    Write-Host 'Einrichtung abgeschlossen. Der Server wurde auf Wunsch NICHT gestartet.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Zum Starten diese eine Zeile einfuegen:' -ForegroundColor Yellow
    Write-Host ('  Set-Location C:\Windows\System32; & "' + $harvesterExe + '" ' + ($startArgs -join ' '))
    Write-Host ''
    Write-Host ('Protokoll: ' + $LogFile)
    Write-Host ('Bericht:   ' + $RepFile)
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

Write-Info 'Der Start erfolgt bewusst aus dem Windows-Systemordner. Das ist der'
Write-Info 'eigentliche Test des in 1.2.1 behobenen Pfadfehlers.'
Write-Host ''
Write-Host ('Gleich oeffnet sich die Oberflaeche unter http://127.0.0.1:' + $Port) -ForegroundColor Green
Write-Host 'Dieses Fenster bleibt danach beschaeftigt. Das ist normal. Nicht schliessen.' -ForegroundColor Green
Write-Host 'Beenden spaeter mit Strg+C.' -ForegroundColor Green
Write-Host ''
Write-Host 'Falls die Windows-Firewall nach einer Freigabe fragt: KEINE Freigabe' -ForegroundColor Yellow
Write-Host 'erteilen, "Abbrechen" waehlen. Das Programm soll nur lokal erreichbar sein.' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Hinweis zum Protokoll: Strg+C beendet den Server UND dieses Skript. Das' -ForegroundColor Gray
Write-Host 'Protokoll endet deshalb an dieser Stelle. Das ist normal und vollstaendig -' -ForegroundColor Gray
Write-Host 'alles Pruefbare steht bereits darueber.' -ForegroundColor Gray
Write-Host ''

Add-Result -Name 'serve' -State 'started' -Detail ('Server gestartet aus C:\Windows\System32 auf Port ' + $Port + '.')
Save-Report

Set-Location C:\Windows\System32
& $harvesterExe @startArgs

$code = $LASTEXITCODE
Write-Host ''
if ($code -eq 0) {
    Write-Host 'Der Server wurde sauber beendet.' -ForegroundColor Green
} else {
    Write-Host ('Der Server endete mit Code ' + $code + '.') -ForegroundColor Yellow
    Write-Host 'Code 3 bedeutet Teilerfolg und ist kein Fehler.' -ForegroundColor Yellow
}
Add-Result -Name 'serve' -State 'ended' -Detail ('exit code ' + $code)
Save-Report

Write-Host ''
Write-Host ('Protokoll: ' + $LogFile)
Write-Host ('Bericht:   ' + $RepFile)
Write-Host 'Bitte diese beiden Dateien zurueckschicken. Screenshots sind nicht noetig.'
try { Stop-Transcript | Out-Null } catch { }
