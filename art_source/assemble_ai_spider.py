#!/usr/bin/env python3
"""Assemble the isolated spider redraw using the constrained 32 px pipeline."""

from pathlib import Path

import assemble_ai_rat as pipeline


ROOT = Path(__file__).resolve().parents[1]
pipeline.SOURCE = ROOT / "art_source" / "modern_pose_refs" / "spider_idle_front_right.png"
pipeline.OUTPUT = ROOT / "assets" / "spider_sheet.png"
pipeline.TARGET_SIZE = (30, 22)

if __name__ == "__main__":
    pipeline.main()
