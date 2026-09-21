<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Suivi SafeRide en direct</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<style>
  html,body{margin:0;height:100%;font-family:system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;background:#f4f6fb;color:#1b2f6b}
  #carte{position:fixed;inset:0;z-index:0}
  .barre{position:fixed;top:0;left:0;right:0;z-index:10;background:rgba(15,98,254,.97);color:#fff;padding:10px 14px;display:flex;align-items:center;gap:10px;box-shadow:0 2px 8px rgba(0,0,0,.25)}
  .logo{font-weight:800;font-size:15px;letter-spacing:.3px}
  .pastille{width:9px;height:9px;border-radius:50%;background:#4ade80;box-shadow:0 0 0 0 rgba(74,222,128,.7);animation:pulse 1.6s infinite}
  @keyframes pulse{0%{box-shadow:0 0 0 0 rgba(74,222,128,.7)}70%{box-shadow:0 0 0 9px rgba(74,222,128,0)}100%{box-shadow:0 0 0 0 rgba(74,222,128,0)}}
  #statutTexte{font-size:12px;opacity:.92;margin-left:auto;text-align:right;line-height:1.3}
  .fiche{position:fixed;left:10px;right:10px;bottom:10px;z-index:10;background:#fff;border-radius:14px;padding:12px 14px;box-shadow:0 4px 18px rgba(10,25,70,.22);font-size:13px}
  .ligne{display:flex;justify-content:space-between;gap:12px;padding:2px 0}
  .cle{color:#6b7a99}
  .val{font-weight:600;text-align:right}
  .fini{background:#fff3f3;border:1px solid #e8b4b4}
  #msgFin{display:none;text-align:center;font-weight:700;color:#b3261e}
  .voiture{background:#0f62fe;border:3px solid #fff;border-radius:50%;box-shadow:0 1px 6px rgba(0,0,0,.4)}
</style>
</head>
<body>
<div class="barre">
  <span class="pastille" id="pastille"></span>
  <span class="logo">SafeRide AI</span>
  <span style="font-size:12px;opacity:.85">Suivi en direct</span>
  <span id="statutTexte">Connexion…</span>
</div>
<div id="carte"></div>
<div class="fiche" id="fiche">
  <div class="ligne"><span class="cle">Destination</span><span class="val" id="dest"><?= htmlspecialchars($destination ?: '—', ENT_QUOTES) ?></span></div>
  <div class="ligne"><span class="cle">Passager</span><span class="val" id="pass">—</span></div>
  <div class="ligne"><span class="cle">Transporteur</span><span class="val" id="trans">—</span></div>
  <div class="ligne"><span class="cle">Vitesse</span><span class="val" id="vit">—</span></div>
  <div class="ligne"><span class="cle">Dernière position</span><span class="val" id="maj">—</span></div>
  <div class="ligne" id="ligneFrais" style="display:none"><span id="msgFrais" style="color:#b3261e;font-weight:700"></span></div>
  <div class="ligne" id="ligneFin" style="display:none"><span id="msgFin"></span></div>
</div>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
// Secours si unpkg est injoignable (réseau opérateur) : second CDN.
if (!window.L) {
  document.write('<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"><\/script>');
}
</script>
<script>
(function () {
  var token = <?= json_encode($token) ?>;
  var actif = <?= json_encode($actif) ?>;
  // Vue par défaut sur Douala : sans elle, Leaflet démarre à [0,0] (océan)
  // tant qu'aucune position/itinéraire n'est reçu — "carte vide".
  var map = L.map('carte', { zoomControl: true }).setView([4.05, 9.7679], 12);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, attribution: '&copy; OpenStreetMap'
  }).addTo(map);

  var markerVoiture = null, polyPrevu = null, polyReel = null, centre = false;
  var premierEchange = false;

  function temps(iso) {
    if (!iso) return '—';
    var s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
    if (s < 60) return 'il y a ' + s + ' s';
    var m = Math.round(s / 60);
    if (m < 60) return 'il y a ' + m + ' min';
    return 'il y a ' + Math.round(m / 60) + ' h';
  }

  function finir(texte) {
    actif = false;
    var p = document.getElementById('pastille');
    p.style.animation = 'none'; p.style.background = '#b3261e';
    document.getElementById('statutTexte').textContent = 'Suivi terminé';
    document.getElementById('fiche').classList.add('fini');
    var lf = document.getElementById('ligneFin'), mf = document.getElementById('msgFin');
    lf.style.display = 'block'; mf.textContent = texte;
  }

  function rafraichir() {
    if (!actif) return;
    fetch('<?= rtrim(url('/'), '/') ?>/api/v1/public/suivi/' + token + '/data', { headers: { Accept: 'application/json' } })
      .then(function (r) { return r.status === 404 ? Promise.reject('404') : r.json(); })
      .then(function (d) {
        if (!d.actif) { finir('Ce trajet est terminé — le suivi en direct est clos.'); return; }
        premierEchange = true;
        document.getElementById('pass').textContent = d.passager || '—';
        document.getElementById('trans').textContent = (d.transporteur || '—') + (d.vehicule ? ' • ' + d.vehicule : '');
        document.getElementById('dest').textContent = d.destination || '—';
        document.getElementById('statutTexte').textContent = 'En route • maj auto toutes les 7 s';
        var pts = [];
        if (d.planned && d.planned.length) {
          if (!polyPrevu) polyPrevu = L.polyline([], { color: '#9db8f5', weight: 4, dashArray: '6 8' }).addTo(map);
          polyPrevu.setLatLngs(d.planned.map(function (p) { return [p.lat, p.lng]; }));
          pts = d.planned.map(function (p) { return [p.lat, p.lng]; });
        }
        if (d.trail && d.trail.length) {
          var t = d.trail.map(function (p) { return [p[0], p[1]]; });
          if (!polyReel) polyReel = L.polyline([], { color: '#0f62fe', weight: 5, opacity: .9 }).addTo(map);
          polyReel.setLatLngs(t);
          pts = pts.concat(t);
        }
        if (d.position) {
          var pos = [d.position.lat, d.position.lng];
          pts.push(pos);
          if (!markerVoiture) {
            markerVoiture = L.marker(pos, {
              icon: L.divIcon({ className: '', html: '<div class="voiture" style="width:22px;height:22px"></div>', iconSize: [22, 22], iconAnchor: [11, 11] })
            }).addTo(map);
          }
          markerVoiture.setLatLng(pos);
          document.getElementById('vit').textContent = Math.round(d.position.vitesse || 0) + ' km/h';
          document.getElementById('maj').textContent = temps(d.position.captured_at);
          // Fraîcheur : si le dernier point a plus de 2 min (téléphone hors
          // ligne, app tuée, plus de GPS), on l'affiche clairement — le lien
          // reste valable mais la position n'est plus du temps réel.
          try {
            var ageS = Math.round((new Date(d.serveur_now).getTime() - new Date(d.position.captured_at).getTime()) / 1000);
            var lf2 = document.getElementById('ligneFrais'), mf2 = document.getElementById('msgFrais');
            if (ageS > 120) {
              lf2.style.display = 'block';
              mf2.textContent = 'Position plus actualisée (téléphone hors ligne ?) — dernier point ' + temps(d.position.captured_at) + '.';
            } else {
              lf2.style.display = 'none'; mf2.textContent = '';
            }
          } catch (e) { /* affichage déjà à jour, pas bloquant */ }
        }
        if (pts.length) {
          if (!centre) { map.fitBounds(L.latLngBounds(pts).pad(0.15)); centre = true; }
          else if (d.position) map.panTo([d.position.lat, d.position.lng], { animate: true, duration: .8 });
        } else if (premierEchange && !d.position) {
          // Trajet actif mais AUCUNE donnée (pas de destination, pas encore
          // de point GPS : SOS déclenché au démarrage). On le dit au lieu
          // d'une carte muette — la position apparaîtra dès le 1er fix.
          document.getElementById('statutTexte').textContent = 'En attente de la première position GPS…';
        }
      })
      .catch(function () {
        document.getElementById('statutTexte').textContent = 'Reconnexion…';
      });
  }

  if (!actif) { finir('Ce trajet est terminé — le suivi en direct est clos.'); }
  else { rafraichir(); setInterval(rafraichir, 7000); }
})();
</script>
</body>
</html>
