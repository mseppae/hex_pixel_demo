#!/usr/bin/env python3
"""Assemble the isolated slime redraw using the constrained 32 px pipeline."""

from pathlib import Path

import assemble_ai_rat as pipeline


ROOT = Path(__file__).resolve().parents[1]
pipeline.SOURCE = ROOT / "art_source" / "modern_pose_refs" / "slime_idle_front_right.png"
pipeline.OUTPUT = ROOT / "assets" / "slime_sheet.png"
pipeline.TARGET_SIZE = (29, 24)

if __name__ == "__main__":
    pipeline.main()
