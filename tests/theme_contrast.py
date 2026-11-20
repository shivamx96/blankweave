#!/usr/bin/env python3
"""Run the shared theme contrast assertions."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'defaults/shell'))
from theme_contrast import main

if __name__ == '__main__':
    main()
