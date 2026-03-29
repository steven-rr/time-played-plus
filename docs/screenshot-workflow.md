# Screenshot Workflow for CurseForge

## Synthetic Data

WoW overwrites SavedVariables on logout, so you must fully close WoW before writing synthetic data.

### Steps
1. **Backup**: Copy `WTF/Account/KARINSTEVE/SavedVariables/TimePlayed_Plus.lua` to `TimePlayed_Plus.lua.backup` in project root
2. **Close WoW completely** (not /reload — WoW will overwrite the file)
3. **Write synthetic data** to the SavedVariables file
4. **Log in**, take screenshots, log out
5. **Restore**: Copy `.backup` back over the SavedVariables file

### Synthetic Data Guidelines
- Characters: Woldorogue (most playtime), Woldomage, Wchi, Woldosauros — all on Stormrage
- ~10 days of sessions, multiple per day per character
- Today should have ~4h for Woldorogue (matches the hero number)
- Use local timestamps so "today" sessions align with local midnight
- Include some `afkDuration` entries for realism
- Sort sessions by startTime

## Image Resizing

CurseForge has a **2MB file size limit**.

Screenshots are PNGs from `C:\Users\steve\OneDrive\Pictures\Screenshots`.

### Conversion Script
```python
from PIL import Image
import os

MAX_SIZE = 2 * 1024 * 1024  # 2MB

path = "screenshot.png"
out_path = path.replace(".png", ".jpg")
img = Image.open(path).convert("RGB")

# Binary search for highest quality under 2MB
lo, hi, best_q = 95, 100, 95
while lo <= hi:
    mid = (lo + hi) // 2
    img.save(out_path, "JPEG", quality=mid, subsampling=0, optimize=True)
    if os.path.getsize(out_path) <= MAX_SIZE:
        best_q = mid
        lo = mid + 1
    else:
        hi = mid - 1

img.save(out_path, "JPEG", quality=best_q, subsampling=0, optimize=True)
```

Key settings: `subsampling=0` (no chroma subsampling), `optimize=True`, quality 99 typically fits 1919x1079 under 2MB with no resize needed.
