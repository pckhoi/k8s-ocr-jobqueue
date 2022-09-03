#!/usr/bin/env python3

import os
import argparse
import tempfile
import subprocess
import json

from tqdm import tqdm
import pypdfium2 as pdfium


SOURCE_BUCKET = ""
KUSTOMIZE_DIR = ""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Enqueue PDF files for OCR processing."
    )
    parser.add_argument(
        "paths",
        metavar="PATH",
        type=str,
        nargs="+",
        help="a path that contain PDF files to be enqueued. Files that already exist in the queue will be ignored.",
    )
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as tmpdirname:
        for path in args.paths:
            path = path.rstrip("/")
            head, _ = os.path.split(path)
            for root, _, files in os.walk(path):
                relroot = os.path.relpath(root, head)
                for file in files:
                    if not file.endswith(".pdf"):
                        continue
                    filepath = os.path.join(root, file)
                    with pdfium.PdfDocument(filepath) as pdf:
                        for ind, img in enumerate(
                            tqdm(
                                pdf.render_topil(scale=2),
                                desc="split %s to images" % json.dumps(file),
                            )
                        ):
                            filepath = os.path.abspath(
                                os.path.join(
                                    tmpdirname, relroot, file, "%03d.png" % (ind + 1,)
                                )
                            )
                            os.makedirs(os.path.dirname(filepath), exist_ok=True)
                            img.save(filepath, "PNG")
            subprocess.run(
                [
                    "gsutil",
                    "-m",
                    "rsync",
                    "-c",
                    "-i",
                    "-J",
                    "-r",
                    tmpdirname,
                    "gs://%s" % (SOURCE_BUCKET,),
                ],
                check=True,
            )
    subprocess.run(
        [
            "bash",
            "-c",
            "kustomize build %s | kubectl apply -f -" % KUSTOMIZE_DIR,
        ],
    )
