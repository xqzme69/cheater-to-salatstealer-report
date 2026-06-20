[CmdletBinding()]
param(
    [ValidateSet('Install', 'Check', 'Remove')]
    [string]$Mode = 'Install',

    [switch]$ResolveAndBlockCurrentIps,

    [switch]$NoQuarantine
)

$ErrorActionPreference = 'Stop'

$Tag = 'CheaterToGuard'
$HostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$HostsBegin = "# BEGIN $Tag"
$HostsEnd = "# END $Tag"
$StateDir = Join-Path $env:ProgramData $Tag
$QuarantineDir = Join-Path $StateDir 'Quarantine'
$FirewallRuleName = "$Tag C2 IP block"
$UnknownExeAsrRule = '01443614-cd74-433a-b99e-2ecdc07bfc25e'

$C2Domains = @(
    'salator.es',
    'wruser.org',
    'websalat.top',
    'salat.cn',
    'wrat.in',
    'sa1atik.cn'
)

$WebRatDomains = @(
    'webrat.org',
    'webrat.es',
    'webrat.uk',
    'webrat.top',
    'webr.at',
    'webrat.ru',
    'zvzvgoida.cn'
)

$BlockDomains = @($C2Domains + $WebRatDomains | Sort-Object -Unique)

$DirectInfraIps = @(
    '2.59.219.233',
    '57.129.43.114'
)

$MutexIocs = @(
    'Global\WEBR_CLMBI2WZW32H'
)

$KnownSha256 = @{
    'A4E6487B6AE37F9C8579BA5FFE8E81C1A046200DC5619C77AFED1782CDD8962C' = 'Update_2026-05-14.rar'
    '489B39A5DBF2679BD9A4C4B08CC1A367BE51F44CB80F4C30F084D5503B2E4991' = 'skins.dll ZIP payload'
    'FFCB7944200B7BD402D9F555E054980F40126D059E0A0FE2B60486DD0C758312' = 'packed Updater.exe'
    'D8ED4BA2515A7867F6650B9A128A464E92765549201BFE94715967A843B906D5' = 'UPX-unpacked Updater.exe'
    '387C5A3DE4727165ACEE17CB48831D317B53EE29B80C4FA6B66AFAC9733D4805' = 'VMRay dropped copy: spoolsv.exe / explorer.exe'
    '0B0791877B137B46022EC548F76D824983206F32EC58D8CB20A3A21B9F1A06A9' = 'Client\Update.exe'
    '92F25A46E5AFCBA7FE02EACEDC29E8BB613A6D575B2C41D2584F67E6CC211E80' = 'related ANY.RUN sample'
}

$SuspiciousTextPattern = 'WEBR|sa1at|wruser|salator|websalat|sa1atik|wrat|webrat|Update_2026|skins\.dll|\\AppData\\Local\\Packages\\explorer\.exe|\\Program Files \(x86\)\\Microsoft\\spoolsv\.exe'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    if (-not $PSCommandPath) {
        throw 'Cannot self-elevate because script path is unavailable'
    }

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Mode', $Mode
    )
    if ($ResolveAndBlockCurrentIps) {
        $args += '-ResolveAndBlockCurrentIps'
    }
    if ($NoQuarantine) {
        $args += '-NoQuarantine'
    }

    Write-Result INFO 'admin rights required; opening UAC prompt'
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $args
    exit
}

function Write-Result {
    param(
        [ValidateSet('OK', 'WARN', 'BAD', 'INFO')]
        [string]$Status,
        [string]$Message
    )

    $color = switch ($Status) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'BAD' { 'Red' }
        default { 'Cyan' }
    }

    Write-Host ("[{0}] {1}" -f $Status, $Message) -ForegroundColor $color
}

if ($Mode -in @('Install', 'Remove') -and -not (Test-IsAdministrator)) {
    Invoke-SelfElevate
}

function Remove-GuardHostsBlock {
    param([string]$Text)

    $pattern = "(?ms)^$([regex]::Escape($HostsBegin))\r?\n.*?^$([regex]::Escape($HostsEnd))\r?\n?"
    [regex]::Replace($Text, $pattern, '')
}

function Install-HostsBlock {
    $text = if (Test-Path -LiteralPath $HostsPath) { Get-Content -LiteralPath $HostsPath -Raw } else { '' }
    $clean = Remove-GuardHostsBlock $text
    $backup = "$HostsPath.$((Get-Date).ToString('yyyyMMddHHmmss')).bak"
    Copy-Item -LiteralPath $HostsPath -Destination $backup -Force

    $block = @($HostsBegin)
    foreach ($domain in $BlockDomains) {
        $block += "0.0.0.0 $domain"
        $block += "::1 $domain"
    }
    $block += $HostsEnd

    Set-Content -LiteralPath $HostsPath -Value (($clean.TrimEnd(), ($block -join [Environment]::NewLine)) -join ([Environment]::NewLine * 2)) -Encoding ASCII
    ipconfig /flushdns | Out-Null
    Write-Result OK "hosts block installed; backup: $backup"
}

function Remove-HostsBlock {
    if (-not (Test-Path -LiteralPath $HostsPath)) {
        Write-Result WARN "hosts file not found"
        return
    }

    $text = Get-Content -LiteralPath $HostsPath -Raw
    Set-Content -LiteralPath $HostsPath -Value (Remove-GuardHostsBlock $text).TrimEnd() -Encoding ASCII
    ipconfig /flushdns | Out-Null
    Write-Result OK "hosts block removed"
}

function Test-HostsBlock {
    if (-not (Test-Path -LiteralPath $HostsPath)) {
        Write-Result BAD "hosts file not found"
        return
    }

    $text = Get-Content -LiteralPath $HostsPath -Raw
    foreach ($domain in $BlockDomains) {
        $pattern = "(?mi)^\s*(0\.0\.0\.0|127\.0\.0\.1|::1)\s+$([regex]::Escape($domain))(\s|$)"
        if ($text -match $pattern) {
            Write-Result OK "hosts blocks $domain"
        } else {
            Write-Result BAD "hosts does not block $domain"
        }
    }
}

function Install-DefenderHardening {
    if (-not (Get-Command Set-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Result WARN "Defender PowerShell cmdlets not available"
        return
    }

    try {
        Set-MpPreference -PUAProtection Enabled
        Write-Result OK "Defender PUA protection enabled"
    } catch {
        Write-Result WARN "could not enable PUA protection: $($_.Exception.Message)"
    }

    try {
        Set-MpPreference -EnableNetworkProtection Enabled
        Write-Result OK "Defender Network Protection enabled"
    } catch {
        Write-Result WARN "could not enable Network Protection: $($_.Exception.Message)"
    }

    try {
        Add-MpPreference -AttackSurfaceReductionRules_Ids $UnknownExeAsrRule -AttackSurfaceReductionRules_Actions Enabled
        Write-Result OK "ASR unknown executable rule enabled"
    } catch {
        Write-Result WARN "could not enable ASR rule: $($_.Exception.Message)"
    }
}

function Test-DefenderHardening {
    if (-not (Get-Command Get-MpPreference -ErrorAction SilentlyContinue)) {
        Write-Result WARN "Defender PowerShell cmdlets not available"
        return
    }

    $mp = Get-MpPreference
    if ("$($mp.PUAProtection)" -match 'Enabled|1') {
        Write-Result OK "PUA protection is enabled"
    } else {
        Write-Result WARN "PUA protection is not enabled"
    }

    if ("$($mp.EnableNetworkProtection)" -match 'Enabled|1') {
        Write-Result OK "Network Protection is enabled"
    } else {
        Write-Result WARN "Network Protection is not enabled"
    }

    $ids = @($mp.AttackSurfaceReductionRules_Ids | ForEach-Object { "$_".ToLowerInvariant() })
    $actions = @($mp.AttackSurfaceReductionRules_Actions)
    $index = [array]::IndexOf($ids, $UnknownExeAsrRule)
    if ($index -ge 0 -and "$($actions[$index])" -match 'Enabled|1') {
        Write-Result OK "ASR unknown executable rule is enabled"
    } else {
        Write-Result WARN "ASR unknown executable rule is not enabled"
    }
}

function Install-FirewallIpBlock {
    if (-not (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue)) {
        Write-Result WARN "firewall cmdlets not available"
        return
    }

    $ips = @($DirectInfraIps | Sort-Object -Unique)
    if (-not $ips) {
        Write-Result WARN "no direct infra IPs configured"
        return
    }

    Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $FirewallRuleName -Direction Outbound -Action Block -RemoteAddress $ips -Profile Any | Out-Null
    Write-Result OK "firewall blocks direct infra IPs: $($ips -join ', ')"
}

function Remove-FirewallIpBlock {
    $rules = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
    if ($rules) {
        $rules | Remove-NetFirewallRule
        Write-Result OK "firewall C2 IP rule removed"
    }
}

function Test-FirewallIpBlock {
    $rules = Get-NetFirewallRule -DisplayName $FirewallRuleName -ErrorAction SilentlyContinue
    if ($rules) {
        Write-Result OK "firewall C2 IP rule exists"
    } else {
        Write-Result INFO "firewall C2 IP rule not installed"
    }
}

function Get-SuspiciousDownloadFiles {
    $roots = @(
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        $env:TEMP,
        (Join-Path $env:LOCALAPPDATA 'Temp'),
        (Join-Path $env:LOCALAPPDATA 'Packages'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        $env:ProgramData,
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique

    $namePattern = '^(Update_2026.*\.rar(\.bin)?|Updater\.exe|Update\.exe|skins\.dll|spoolsv\.exe|explorer\.exe)$'
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $namePattern }
    }
}

function Invoke-KnownHashScan {
    param([switch]$Quarantine)

    $hits = 0
    foreach ($file in Get-SuspiciousDownloadFiles) {
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        } catch {
            Write-Result WARN "could not hash $($file.FullName): $($_.Exception.Message)"
            continue
        }

        if (-not $KnownSha256.ContainsKey($hash)) {
            continue
        }

        $hits++
        $label = $KnownSha256[$hash]
        if (-not $Quarantine) {
            Write-Result BAD "known sample found: $($file.FullName) [$label]"
            continue
        }

        New-Item -ItemType Directory -Path $QuarantineDir -Force | Out-Null
        $dest = Join-Path $QuarantineDir ("{0}.{1}.blocked" -f $file.Name, (Get-Date).ToString('yyyyMMddHHmmss'))
        Move-Item -LiteralPath $file.FullName -Destination $dest -Force
        Write-Result BAD "quarantined known sample: $dest [$label]"
    }

    if ($hits -eq 0) {
        Write-Result OK "known sample hashes not found in Downloads/Desktop/Temp"
    }
}

function Test-MutexIocs {
    foreach ($mutexName in $MutexIocs) {
        try {
            $mutex = [Threading.Mutex]::OpenExisting($mutexName)
            $mutex.Dispose()
            Write-Result BAD "live mutex found: $mutexName"
        } catch {
            Write-Result OK "mutex not present: $mutexName"
        }
    }
}

function Get-FileHashSafe {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    } catch {
        $null
    }
}

function Test-ProcessIocs {
    $bad = 0
    $windows = $env:WINDIR.TrimEnd('\')
    $expectedExplorer = (Join-Path $windows 'explorer.exe').ToLowerInvariant()
    $expectedSpoolsv = (Join-Path $windows 'System32\spoolsv.exe').ToLowerInvariant()

    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(Update|Updater|explorer|spoolsv|powershell|pwsh|svchost)\.exe$' }

    foreach ($proc in $processes) {
        $path = "$($proc.ExecutablePath)"
        $pathLower = $path.ToLowerInvariant()
        $hash = Get-FileHashSafe $path

        if ($hash -and $KnownSha256.ContainsKey($hash)) {
            $bad++
            Write-Result BAD "known malware hash in running process: $($proc.Name) pid=$($proc.ProcessId) path=$path [$($KnownSha256[$hash])]"
            continue
        }

        if ($proc.Name -ieq 'spoolsv.exe' -and $pathLower -and $pathLower -ne $expectedSpoolsv) {
            $bad++
            Write-Result BAD "spoolsv.exe running from suspicious path: pid=$($proc.ProcessId) path=$path"
            continue
        }

        if ($proc.Name -ieq 'explorer.exe' -and $pathLower -and $pathLower -ne $expectedExplorer) {
            $bad++
            Write-Result BAD "explorer.exe running from suspicious path: pid=$($proc.ProcessId) path=$path"
            continue
        }

        if ($proc.Name -match '^(Update|Updater)\.exe$' -and $path -match '\\(Downloads|Desktop|Temp|AppData)\\') {
            Write-Result WARN "updater-like process from user-writable path: pid=$($proc.ProcessId) path=$path"
        }
    }

    if ($bad -eq 0) {
        Write-Result OK "no live process IOC found"
    }
}

function Test-PersistenceIocs {
    $hits = 0

    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($key in $runKeys) {
        if (-not (Test-Path $key)) {
            continue
        }
        $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        foreach ($prop in $props.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
            if ("$($prop.Value)" -match $SuspiciousTextPattern) {
                $hits++
                Write-Result BAD "suspicious Run key: $key :: $($prop.Name) = $($prop.Value)"
            }
        }
    }

    $startupRoots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $startupRoots) {
        Get-ChildItem -LiteralPath $root -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'Update|Updater|spoolsv|explorer|skins' } |
            ForEach-Object {
                $hits++
                Write-Result BAD "suspicious startup file: $($_.FullName)"
            }
    }

    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $task = $_
        foreach ($action in @($task.Actions)) {
            $text = "$($action.Execute) $($action.Arguments)"
            if ($text -match $SuspiciousTextPattern) {
                $hits++
                Write-Result BAD "suspicious scheduled task: $($task.TaskPath)$($task.TaskName) -> $text"
            }
        }
    }

    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
        $text = "$($_.Name) $($_.DisplayName) $($_.PathName)"
        if ($text -match $SuspiciousTextPattern) {
            $hits++
            Write-Result BAD "suspicious service: $($_.Name) -> $($_.PathName)"
        }
    }

    Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue | ForEach-Object {
        $text = "$($_.Name) $($_.ExecutablePath) $($_.CommandLineTemplate)"
        if ($text -match $SuspiciousTextPattern) {
            $hits++
            Write-Result BAD "suspicious WMI command consumer: $($_.Name) -> $($_.CommandLineTemplate)"
        }
    }

    if ($hits -eq 0) {
        Write-Result OK "no persistence IOC found"
    }
}

function Test-NetworkIocs {
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        Write-Result WARN "Get-NetTCPConnection not available"
        return
    }

    $hits = 0
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $DirectInfraIps -contains $_.RemoteAddress } |
        ForEach-Object {
            $hits++
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            Write-Result BAD "connection to direct WebRat infra: $($_.RemoteAddress):$($_.RemotePort) pid=$($_.OwningProcess) process=$($proc.ProcessName) path=$($proc.Path)"
        }

    if ($hits -eq 0) {
        Write-Result OK "no live TCP connection to direct WebRat infra"
    }
}

switch ($Mode) {
    'Install' {
        Install-HostsBlock
        Install-DefenderHardening
        if ($ResolveAndBlockCurrentIps) {
            Install-FirewallIpBlock
        }
        if (-not $NoQuarantine) {
            Invoke-KnownHashScan -Quarantine
        }
    }
    'Check' {
        Test-HostsBlock
        Test-DefenderHardening
        Test-FirewallIpBlock
        Test-MutexIocs
        Test-ProcessIocs
        Test-PersistenceIocs
        Test-NetworkIocs
        Invoke-KnownHashScan
    }
    'Remove' {
        Remove-HostsBlock
        Remove-FirewallIpBlock
        Write-Result WARN "Defender hardening is intentionally left enabled; disable it manually only if it breaks your workflow"
    }
}
