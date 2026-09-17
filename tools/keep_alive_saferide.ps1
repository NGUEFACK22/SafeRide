# Keep-alive SafeRide : maintient l'instance Render éveillée (tier gratuit).
# Ping GET / toutes les 5 min via la Tâche Planifiée Windows "KeepAliveSafeRide".
# Arrêt du serveur si Render est déjà en train de dormir : le ping le réveille (~30-60 s).

$url = 'https://saferide-api-udra.onrender.com/'
$log = 'C:\PROJET1\soutenance\tools\keep_alive.log'

try {
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 50
    Add-Content -Path $log -Value ("{0} OK {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $resp.StatusCode)
} catch {
    Add-Content -Path $log -Value ("{0} ECHEC : {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
}