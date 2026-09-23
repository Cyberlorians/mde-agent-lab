[CmdletBinding()]
param([switch]$SkipCopilotApp)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Run this installer from 64-bit PowerShell on Windows x64.'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell with Run as administrator, then run this installer again.'
}
if ($identity.IsSystem -and -not $SkipCopilotApp) {
    throw 'The Copilot Store app requires a signed-in user. Use -SkipCopilotApp for SYSTEM deployments.'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$staging = Join-Path $env:ProgramData 'AgentLabInstall'
$prefix = Join-Path $env:ProgramFiles 'AgentCLIs'
New-Item -ItemType Directory -Path $staging, $prefix -Force | Out-Null

function Install-VerifiedMsi {
    param([string]$Uri, [string]$Name, [string]$PublisherPattern, [string]$ExpectedDigest)
    $destination = Join-Path $staging $Name
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $destination -TimeoutSec 240
    if ($ExpectedDigest) {
        $actualDigest = 'sha256:' + (Get-FileHash $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualDigest -ne $ExpectedDigest) { throw "Installer checksum mismatch: $Name" }
    }
    $signature = Get-AuthenticodeSignature $destination
    if ($PublisherPattern -and ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $PublisherPattern)) {
        throw "Installer signature verification failed: $Name ($($signature.Status))."
    }
    if (-not $PublisherPattern -and -not $ExpectedDigest) { throw 'Installer integrity verification is required.' }
    $logPath = Join-Path $staging "$Name.log"
    $process = Start-Process msiexec.exe -ArgumentList "/i `"$destination`" /qn /norestart /L*v `"$logPath`"" -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "Installer failed: $Name, exit $($process.ExitCode)." }
    Write-Output "Installed $Name; signature: $($signature.Status); published digest checked: $([bool]$ExpectedDigest); exit $($process.ExitCode)"
    if ($process.ExitCode -eq 3010) { Write-Warning 'Windows reports a reboot is required. No automatic restart was performed.' }
}

$pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (-not (Test-Path $pwsh)) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -Headers @{'User-Agent' = 'AgentLab-Installer'}
    $asset = @($release.assets | Where-Object { $_.name -match '^PowerShell-.*-win-x64\.msi$' })
    if ($asset.Count -ne 1) { throw 'Could not uniquely identify the official PowerShell installer.' }
    Install-VerifiedMsi -Uri $asset[0].browser_download_url -Name $asset[0].name -PublisherPattern 'Microsoft Corporation'
}
& $pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0) { throw 'PowerShell verification failed.' }

$node = Join-Path $env:ProgramFiles 'nodejs\node.exe'
$nodeSupported = $false
if (Test-Path $node) {
    $nodeVersion = & $node --version
    $nodeSupported = $LASTEXITCODE -eq 0 -and [int]($nodeVersion.TrimStart('v').Split('.')[0]) -ge 22
}
if (-not $nodeSupported) {
    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    $release = $releases | Where-Object { $_.lts -and [int]($_.version.TrimStart('v').Split('.')[0]) -ge 22 } | Select-Object -First 1
    if (-not $release) { throw 'No supported Node.js LTS release found.' }
    $name = "node-$($release.version)-x64.msi"
    Install-VerifiedMsi -Uri "https://nodejs.org/dist/$($release.version)/$name" -Name $name -PublisherPattern 'OpenJS Foundation|Node.js Foundation'
}
& $node --version
if ($LASTEXITCODE -ne 0) { throw 'Node.js verification failed.' }

$gh = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
if (-not (Test-Path $gh)) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/cli/cli/releases/latest' -Headers @{'User-Agent' = 'AgentLab-Installer'}
    $asset = @($release.assets | Where-Object { $_.name -match '^gh_.*_windows_amd64\.msi$' })
    if ($asset.Count -ne 1 -or $asset[0].digest -notmatch '^sha256:[a-f0-9]{64}$') {
        throw 'Could not identify the official GitHub CLI installer and checksum.'
    }
    Install-VerifiedMsi -Uri $asset[0].browser_download_url -Name $asset[0].name -ExpectedDigest $asset[0].digest
}
& $gh --version
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI verification failed.' }
$env:Path = "$env:ProgramFiles\GitHub CLI;$env:ProgramFiles\nodejs;$env:ProgramFiles\PowerShell\7;$prefix;$env:Path"
$npm = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
& $npm install --global --prefix $prefix --registry=https://registry.npmjs.org/ --no-audit --no-fund --allow-scripts=@anthropic-ai/claude-code '@anthropic-ai/claude-code@latest' '@openai/codex@latest' '@github/copilot@latest'
if ($LASTEXITCODE -ne 0) { throw "Agent package installation failed: exit $LASTEXITCODE." }

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$entries = @($machinePath -split ';' | Where-Object { $_ })
foreach ($directory in @($prefix, "$env:ProgramFiles\GitHub CLI", "$env:ProgramFiles\nodejs", "$env:ProgramFiles\PowerShell\7")) {
    if ($entries -notcontains $directory) { $entries += $directory }
}
[Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'Machine')

foreach ($name in @('claude', 'codex', 'copilot')) {
    $launcher = Join-Path $prefix "$name.cmd"
    if (-not (Test-Path $launcher)) { throw "Missing launcher: $name" }
    $ErrorActionPreference = 'Continue'
    try {
        $version = & $launcher --version 2>&1
        $versionExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if ($versionExitCode -ne 0) { throw "$name version check failed: $version" }
    [pscustomobject]@{Agent = $name; Version = ($version -join ' '); Launcher = $launcher} | ConvertTo-Json -Compress
}
$sense = Get-Service Sense -ErrorAction SilentlyContinue
$onboarding = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status' -ErrorAction SilentlyContinue
[pscustomobject]@{SensorStatus = [string]$sense.Status; OnboardingState = $onboarding.OnboardingState} | ConvertTo-Json -Compress
if ($sense.Status -ne 'Running' -or $onboarding.OnboardingState -ne 1) {
    Write-Warning 'MDE onboarding or sensor health needs attention. This installer does not onboard devices or change security settings.'
}

if (-not $SkipCopilotApp) {
    $app = Get-AppxPackage -Name Microsoft.Copilot
    if (-not $app) {
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) { throw 'CLIs installed, but App Installer (winget) is required for the Copilot Store app.' }
        & $winget.Source install --id 9NHT9RB2F4HD --exact --source msstore --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { throw "CLIs installed, but Copilot Store installation failed with exit $LASTEXITCODE. Check Microsoft Store access and policy." }
        $app = Get-AppxPackage -Name Microsoft.Copilot
    }
    if (-not $app) { throw 'Copilot Store app registration could not be verified for the current user.' }
    $app | Select-Object Name, Version, PackageFullName | ConvertTo-Json -Compress
} else {
    Write-Output 'Copilot desktop app explicitly skipped. Run without -SkipCopilotApp in the signed-in user session to install it.'
}
Write-Output 'Installation checks complete. Open a new terminal before using claude, codex, copilot, or gh. Authentication is not configured.'