"""
Quantifie ecapa_tdnn.onnx (84 Mo) en int8 dynamique -> ecapa_tdnn_int8.onnx (~20 Mo)
Usage:
  pip install onnx onnxruntime
  python quantize_ecapa.py

Le mobile charge automatiquement ecapa_tdnn_int8.onnx s'il existe, sinon retombe sur ecapa_tdnn.onnx.
Voir VoiceprintService.ensureLoaded() : essaye int8 d'abord.
"""
from pathlib import Path

try:
    from onnxruntime.quantization import quantize_dynamic, QuantType
except ImportError:
    print("pip install onnx onnxruntime")
    raise SystemExit(1)

src = Path(__file__).parent / "ecapa_tdnn.onnx"
dst = Path(__file__).parent / "ecapa_tdnn_int8.onnx"

if not src.exists():
    print(f"Source manquante: {src}")
    raise SystemExit(1)

print(f"Quantification {src} -> {dst} (dynamic int8, ~4x plus petit)...")
quantize_dynamic(
    model_input=str(src),
    model_output=str(dst),
    weight_type=QuantType.QInt8,
)
print(f"OK {dst.stat().st_size/1e6:.1f} MB (orig {src.stat().st_size/1e6:.1f} MB)")
print("Relancez flutter build apk --release pour embarquer la version quantifiée.")
