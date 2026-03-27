# GIF Creation Process for CurseForge

## Why Not Giphy
Giphy downsizes all GIFs to 480px wide — text becomes unreadable. Don't use Giphy for addon demos.

## Recording (OBS)
- Set Recording Quality to "High Quality, Medium File Size" (not "Same as stream")
- Record at 720p, crop to addon area as much as possible
- OBS outputs MKV by default, convert to MP4 with moviepy

## GIF Conversion (Local)
```python
from moviepy import VideoFileClip
from PIL import Image

clip = VideoFileClip('recording.mkv')
clip_trimmed = clip.subclipped(0, min(10, clip.duration))
frames = []
for t in range(0, int(clip_trimmed.duration * 8)):
    frame_time = t / 8.0
    if frame_time >= clip_trimmed.duration: break
    frame = clip_trimmed.get_frame(frame_time)
    img = Image.fromarray(frame)
    img = img.resize((960, 540), Image.LANCZOS)
    img = img.quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    frames.append(img)

frames[0].save('output.gif', save_all=True, append_images=frames[1:],
    duration=125, loop=0, optimize=True)
```

Key settings: 960x540, 8fps, 48 colors, no dithering (keeps text sharp), ~5-10MB output.

## Hosting
- Upload GIF to a GitHub Issue comment (drag and drop)
- Submit the issue to get a permanent URL: `https://github.com/user-attachments/assets/...`
- Close the issue — image URL stays alive
- Embed in CurseForge description source: `<p><img src="URL" alt="Demo"></p>`

## Why This Approach
- CurseForge has 2MB image limit for uploads
- GitHub Issues accepts up to 10MB
- The permanent URL works in CurseForge's HTML
