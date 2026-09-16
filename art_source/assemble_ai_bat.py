#!/usr/bin/env python3
"""Assemble the isolated bat redraw using the constrained 32 px pipeline."""

from pathlib import Path

import assemble_ai_rat as pipeline


ROOT = Path(__file__).resolve().parents[1]
pipeline.SOURCE = ROOT / "art_source" / "modern_pose_refs" / "bat_idle_front_right.png"
pipeline.OUTPUT = ROOT / "assets" / "bat_sheet.png"
pipeline.TARGET_SIZE = (30, 20)

if __name__ == "__main__":
    pipeline.main()
