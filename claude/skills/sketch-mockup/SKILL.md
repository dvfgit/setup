---
name: sketch-mockup
description: Generate hand-drawn pencil-sketch wireframe mockups (Linear "sketch" aesthetic) from a screenshot or description, using HTML/CSS + an SVG displacement filter rendered to PNG via headless Chrome. Use when asked to "make a sketch like the Linear issue image", "generate a wireframe mockup", or recreate a low-fi sketch of a UI screen.
---

# SKETCH-MOCKUP Task

## Objective

Produce a hand-drawn / pencil-sketch wireframe PNG of a UI screen that matches the
Linear "sketch" reference aesthetic: wavy hand-drawn borders, light sketch-paper grain,
grayscale wireframe, and a `✦` sparkle in the bottom-right corner.

There is **no diffusion image generator** in this environment. The look is produced
deterministically: rebuild the UI in HTML/CSS, warp it with an SVG filter, screenshot
with headless Chrome.

## When to use

- "Generate an image like the one on [Linear issue]" where that image is a low-fi sketch.
- Recreating a screenshot as a hand-drawn wireframe for a ticket/brief.
- Any request for a "sketch", "wireframe", or "low-fi mockup" of a screen.

For the *real* app UI, drive the live app instead (`/run`, browser tools). This skill is
only for the stylized sketch artifact.

## Process

1. **Get the reference.** If it's a Linear issue, fetch it with `mcp__linear-server__get_issue`
   then view embedded images via `mcp__linear-server__extract_images` to confirm the target
   aesthetic. If the user gave a screenshot, that is the content to replicate.

2. **Rebuild the screen in HTML/CSS** (see template below). Match layout, labels, columns,
   menus from the source. Keep it grayscale; a single accent color (e.g. a blue `+` button)
   is fine.

3. **Wrap the whole UI in a filtered container** carrying the SVG `pencil` filter, and add
   the translucent sketch-paper overlay + sparkle.

4. **Render to PNG with headless Chrome** (command below). Save to the user's Desktop or the
   scratchpad and `Read` it back to verify before reporting done.

5. **Tune** the wobble (`feDisplacementMap` `scale`) and re-render until it matches.

## HTML template (skeleton)

```html
<!DOCTYPE html><html><head><meta charset="utf-8"/><style>
  * { box-sizing:border-box; margin:0; padding:0; }
  html,body { width:1600px; height:1040px; background:#d6d6d6;
              font-family:'Helvetica Neue',Arial,sans-serif; overflow:hidden; }

  /* translucent sketch-paper grain — NEVER opaque, NEVER over content opaquely */
  body::before { content:""; position:fixed; inset:0; pointer-events:none; z-index:9999;
    background:
      repeating-linear-gradient(115deg, rgba(0,0,0,.02) 0 2px, transparent 2px 6px),
      repeating-linear-gradient(65deg,  rgba(0,0,0,.016) 0 2px, transparent 2px 7px); }

  /* filter wrapper MUST have a real box, else the SVG filter region is empty */
  #sketch { position:fixed; inset:0; filter:url(#pencil) saturate(.18) contrast(1.02); }

  .app { position:absolute; inset:22px; background:#fdfdfd; border:2.5px solid #555;
         border-radius:10px; box-shadow:6px 8px 0 rgba(0,0,0,.08); overflow:hidden; }
  .sparkle { position:absolute; bottom:26px; right:40px; font-size:46px; color:#bdbdbd; }
  /* ...rest of the specific screen markup... */
</style></head><body>
  <svg width="0" height="0">
    <filter id="pencil">
      <feTurbulence type="fractalNoise" baseFrequency="0.015 0.018" numOctaves="4" seed="11" result="noise"/>
      <feDisplacementMap in="SourceGraphic" in2="noise" scale="5.5" xChannelSelector="R" yChannelSelector="G"/>
    </filter>
  </svg>
  <div id="sketch">
    <div class="app"><!-- screen content --><div class="sparkle">✦</div></div>
  </div>
</body></html>
```

## Render command (headless Chrome)

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --no-sandbox \
  --force-device-scale-factor=2 --hide-scrollbars \
  --virtual-time-budget=2500 \
  --window-size=1600,1040 \
  --screenshot="/Users/<you>/Desktop/<name>.png" \
  "file:///abs/path/to/sketch.html"
```

Then `Read` the PNG to verify; iterate on `scale` / `baseFrequency` if needed.

## Do's and Don'ts

- ✅ **Do** give `#sketch` (the filtered wrapper) `position:fixed; inset:0`. A wrapper whose
  only child is `position:absolute` collapses to zero size → empty filter region → blank PNG.
- ✅ **Do** keep the paper overlay translucent (rgba gradients only).
- ✅ **Do** use system fonts and `--virtual-time-budget` so headless paints fully.
- ✅ **Do** use `--force-device-scale-factor=2` for crisp output.
- ❌ **Don't** put an opaque `radial-gradient`/fill in a high-`z-index` overlay — it hides the UI.
- ❌ **Don't** rely on `@import`/Google Fonts in headless — the fetch can stall the screenshot.
- ❌ **Don't** assume the MCP browser is available — `navigate` may be permission-denied;
  the headless `--screenshot` path needs no live browser.

## Known fixes (debug ladder for a blank/wrong PNG)

| Symptom | Cause | Fix |
|---|---|---|
| Only the paper grain / a stray line shows | Opaque overlay on top | Make `body::before` rgba-only, drop opaque fills |
| Whole UI blank, only chrome bar edge | Filter wrapper has 0 size | `#sketch { position:fixed; inset:0 }` |
| Content missing, slow/empty render | Web-font `@import` stalled paint | System fonts + `--virtual-time-budget=2500` |
| Lines too clean (not sketchy) | Displacement too small | Raise `feDisplacementMap` `scale` (~5–6) |
| Lines too jagged/torn | Displacement too large | Lower `scale`, lower `baseFrequency` |

## Quality criteria

- Borders and text show a visible hand-drawn wobble; not a clean screenshot.
- Grayscale wireframe with subtle paper grain and a `✦` sparkle bottom-right.
- Content (labels, rows, menus) matches the source screenshot faithfully.
- Output is a real PNG, verified by reading it back before reporting completion.

## Tunable knobs

- `feDisplacementMap@scale` — wobble strength (the main dial).
- `feTurbulence@baseFrequency` / `numOctaves` / `seed` — texture of the wobble.
- `--window-size` + `inset` — canvas size and margin.
- `--force-device-scale-factor` — output resolution.
