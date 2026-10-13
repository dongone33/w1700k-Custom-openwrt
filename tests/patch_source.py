"""Locate the same shared payload used by the firmware packages checkout."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCHES = Path(os.environ.get('W1700K_PATCHES', ROOT.parent / 'packages/w1700k-patches'))
