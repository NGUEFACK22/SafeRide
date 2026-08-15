# Modèle de biométrie vocale (ECAPA-TDNN, ONNX)

Déposez ici un export ONNX du modèle d'embedding de voix **ECAPA-TDNN**,
nommé exactement `ecapa_tdnn.onnx` :

- Entrée : `waveform` — float32, forme `[1, N]` échantillons (16 kHz mono, valeurs
  normalisées entre -1 et 1).
- Sortie : `embedding` — float32, forme `[1, 192]` (vecteur de voix, 192 dimensions).

Sources possibles : exports communautaires du modèle SpeechBrain
`spkrec-ecapa-voxceleb` sur Hugging Face (formats ONNX ou exports `torch.onnx`).

Sans ce fichier, l'application fonctionne quand même : le SOS vocal retombe sur la
vérification mot-clé (reconnaissance vocale réelle) + empreinte dérivée, sans
biométrie. Une fois le fichier présent, la vérification devient une vraie
biométrie vocale (similarité cosinus ≥ 0.5 entre les embeddings).