"""Convert the prototype's vape detector to Core ML. Build-time only."""

import argparse
import hashlib
import json
from pathlib import Path

import coremltools as ct
import torch
from ultralytics import YOLO

WEIGHTS_SHA256 = "ae9f733fe51eaf0540a3446540867dae26ac91554b6f5a4be7c44407ae3f791a"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("weights", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    weights = args.weights.resolve()
    output = args.output.resolve()
    if output == weights.with_suffix(".mlpackage"):
        parser.error("Specify an output path distinct from the temporary YOLO export.")
    with weights.open("rb") as file:
        if hashlib.file_digest(file, "sha256").hexdigest() != WEIGHTS_SHA256:
            parser.error("Unexpected checkpoint SHA-256.")

    torch.set_num_threads(4)
    model = YOLO(str(weights))
    if model.names != {0: "cigarette", 1: "vape"}:
        raise ValueError(f"Unexpected classes: {model.names}")
    exported = model.export(format="coreml", imgsz=640, nms=False, half=True, device="cpu")
    result = ct.models.MLModel(str(exported), skip_model_load=True)
    result.short_description = "Cigarette and vape detection for Slow Vape"
    result.user_defined_metadata["class_names"] = json.dumps(list(model.names.values()))
    result.user_defined_metadata["weights_sha256"] = WEIGHTS_SHA256
    result.save(str(output))


if __name__ == "__main__":
    main()
