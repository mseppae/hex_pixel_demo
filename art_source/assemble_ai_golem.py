#!/usr/bin/env python3
"""Assemble the isolated golem redraw using the 48x64 large-creature path."""

from pathlib import Path

import assemble_ai_troll as pipeline


ROOT = Path(__file__).resolve().parents[1]
pipeline.SOURCE = ROOT / "art_source" / "modern_pose_refs" / "golem_idle_front_right.png"
pipeline.OUTPUT = ROOT / "assets" / "golem_sheet.png"
pipeline.TARGET_SIZE = (46, 54)

if __name__ == "__main__":
    pipeline.main()
