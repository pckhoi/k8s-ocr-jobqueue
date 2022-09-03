#!/usr/bin/env python3

import sys
import os

import pypdfium2 as pdfium


if __name__ == "__main__":
    os.makedirs(os.path.join(sys.argv[2], sys.argv[1]), exist_ok=True)
    with pdfium.PdfDocument(sys.argv[1]) as pdf:
        for ind, img in enumerate(
            pdf.render_topil(scale=2),
        ):
            img.save(
                os.path.join(sys.argv[2], sys.argv[1], "%03d.png" % (ind + 1,)),
                "PNG",
            )
