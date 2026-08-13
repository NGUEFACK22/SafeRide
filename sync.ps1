# sync.ps1 - Synchronisation automatique du projet vers GitHub.
# À chaque intervalle, détecte les modifications et commit + pousse sur origin/main.
#
# Usage :  dans PowerShell, depuis la racine du projet ->
#          .\sync.ps1
# (Ctrl+C pour arrêter la surveillance)

$repo = $PSScriptRoot
$intervalSeconds = 5

Write-Host "[sync] surveillance de $repo (Ctrl+C pour arreter)..."

while ($true) {
    Set-Location $repo
    $status = git status --porcelain
    if ($status) {
        $msg = "auto-sync: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        git add -A 2>&1 | Out-Null
        git commit -m $msg 2>&1 | Out-Null
        Write-Host "[sync] $(Get-Date -Format 'HH:mm:ss') commit -> $msg"
        $p = Start-Process -NoNewWindow -FilePath "git" -ArgumentList "push","origin","main" -PassThru
        if ($p.WaitForExit(60000)) {
            Write-Host "[sync] push termine (exit $($p.ExitCode))"
        } else {
            $p.Kill()
            Write-Host "[sync] push impossible (pas de reseau ?)"
        }
    }
    Start-Sleep -Seconds $intervalSeconds
}
