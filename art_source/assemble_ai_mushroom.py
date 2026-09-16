#!/usr/bin/env python3
"""Assemble the isolated mushroom redraw using the constrained 32 px pipeline."""

from pathlib import Path

import assemble_ai_rat as pipeline


ROOT = Path(__file__).resolve().parents[1]
pipeline.SOURCE = ROOT / "art_source" / "modern_pose_refs" / "mushroom_idle_front_right.png"
pipeline.OUTPUT = ROOT / "assets" / "mushroom_sheet.png"
# Its distinctive layered cap needs height; this still leaves a transparent
# two-pixel margin within the 32 px gameplay cell.
pipeline.TARGET_SIZE = (27, 28)

if __name__ == "__main__":
    pipeline.main()
