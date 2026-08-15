# Modèle de biométrie vocale (ECAPA-TDNN, ONNX)

Le fichier `ecapa_tdnn.onnx` (84 Mo) est un export ONNX du modèle d'embedding de
voix **ECAPA-TDNN** (`pranjal-pravesh/ecapa_tdnn_onnx`, Hugging Face, licence MIT).
Le graphe inclut l'extraction Fbank + ECAPA : **entrée = waveform 16 kHz mono brute**.

- Entrée : `audio` — float32, forme `[1, N]` échantillons (16 kHz mono, valeurs
  normalisées entre -1 et 1 ; `N` variable, ≥ ~1 s conseillé).
- Sortie : `embedding` — float32, forme `[1, 1, 192]` (vecteur de voix, 192 dimensions).

SHA-256 : `245eb5995cfffd74494862dee33da2b00c1c2579eb0c6703847784e9901ed458`.

Le mobile charge ce modèle via ONNX Runtime (onnxruntime 1.4.1) et envoie
l'embedding au backend, qui compare par similarité cosinus (seuil ≥ 0.5).

Pour re-télécharger : `curl -L -o ecapa_tdnn.onnx https://huggingface.co/pranjal-pravesh/ecapa_tdnn_onnx/resolve/04c3ffe4fd00b3b7853fd57db44e2e531d4817f2/ecapa_tdnn.onnx`

Sans ce fichier, l'application retombe sur la vérification mot-clé seule.