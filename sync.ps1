# sync.ps1 - Synchronisation automatique du projet vers GitHub.
# Surveille backend/ et mobile/ ; à chaque modification (après un délai anti-répétition),
# commit et pousse sur origin/main.
#
# Usage :  dans PowerShell, depuis la racine du projet ->
#          .\sync.ps1
# (Ctrl+C pour arrêter la surveillance)

$repo = $PSScriptRoot
$debounceSeconds = 5
$global:lastChange = [datetime]::MinValue

$watchers = @()
foreach ($sub in @('backend', 'mobile')) {
    $path = Join-Path $repo $sub
    if (-not (Test-Path $path)) { continue }
    $w = New-Object System.IO.FileSystemWatcher
    $w.Path = $path
    $w.IncludeSubdirectories = $true
    $w.NotifyFilter = [IO.NotifyFilters]::FileName -bor [IO.NotifyFilters]::LastWrite -bor [IO.NotifyFilters]::DirectoryName
    $w.EnableRaisingEvents = $true
    $watchers += $w
}

function Sync-Git {
    Set-Location $repo
    git add -A
    $status = git status --porcelain
    if (-not $status) {
        Write-Host "[sync] $(Get-Date -Format 'HH:mm:ss') rien a commiter"
        return
    }
    $msg = "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    git commit -m $msg 2>&1 | Out-Null
    Write-Host "[sync] $(Get-Date -Format 'HH:mm:ss') commit -> $msg"
    $p = Start-Process -NoNewWindow -FilePath "git" -ArgumentList "push","origin","main" -PassThru
    if ($p.WaitForExit(60000)) {
        Write-Host "[sync] push termine (exit $($p.ExitCode))"
    } else {
        $p.Kill()
        Write-Host "[sync] push impossible (pas de réseau ?)"
    }
}

$action = { $global:lastChange = [datetime]::Now }
foreach ($w in $watchers) {
    Register-ObjectEvent $w "Changed" -Action $action | Out-Null
    Register-ObjectEvent $w "Created" -Action $action | Out-Null
    Register-ObjectEvent $w "Deleted" -Action $action | Out-Null
    Register-ObjectEvent $w "Renamed" -Action $action | Out-Null
}

Write-Host "[sync] surveillance de $repo (Ctrl+C pour arreter)..."
while ($true) {
    Start-Sleep -Seconds 2
    if (($global:lastChange -ne [datetime]::MinValue) -and
        (([datetime]::Now - $global:lastChange).TotalSeconds -ge $debounceSeconds)) {
        $global:lastChange = [datetime]::MinValue
        try { Sync-Git } catch { Write-Host "[sync] erreur: $_" }
    }
}
