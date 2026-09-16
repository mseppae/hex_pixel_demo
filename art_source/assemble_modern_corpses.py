#!/usr/bin/env python3
"""Compatibility entry point for rebuilding the current 256x64 objects atlas."""

from modern_objects import ASSETS, build


if __name__ == "__main__":
    build().save(ASSETS / "objects.png")
    print("updated objects.png from the current creature-sheet death poses")
