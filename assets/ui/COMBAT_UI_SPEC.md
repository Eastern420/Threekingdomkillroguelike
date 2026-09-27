# Combat UI Asset Specification

Generated assets are authored for a 16:9 combat HUD and use the existing dark charcoal / gold card language. All PNGs are RGBA unless noted.

## Dodge / Take Hit choice
- Overlay: dim full combat with `Color(0,0,0,0.45)`.
- Panel: centered horizontally, vertically ~52% from top (above player hand). Size **800x240 px**; use `choice_panel_bg.png`.
- Two buttons side by side, gap **24 px**, each **360x192 px** (or scale to **180x96 px** on 1280x720).
- Left = Dodge (cyan), right = Take Hit (vermillion).
- If player has no DODGE in hand: Dodge button modulate gray **0.5**, disabled.
- Focus/hover: gold rim brighten + **1.05 scale**.
- Text is English, clean sans-serif; keep button labels centered in the label area.

## Draw pile (player)
- Anchor: bottom-left, above End Turn / left of hand — suggested position offset **(48, viewport_h - 220)**.
- Slot size: **72x100 px** (same aspect as hand 96x134 scaled ~0.75).
- Texture: `card_back.png`, stack of **2–3 offset shadows** for depth.
- Count badge: gold oval top-right of pile, number = deck remaining.
- Draw animation: spawn TextureRect at pile center, tween **0.28 s cubic** to target hand slot (arc control point mid), fade in first **0.05 s**; then rebuild hand.
- Marker for empty/placeholder layout: `pile_draw_marker.png` at source scale 128x168, or scale to the slot size above.

## Discard pile (player)
- Anchor: bottom-right mirror of draw — **(viewport_w - 48 - 72, viewport_h - 220)**.
- Empty: `pile_discard_marker.png`.
- Non-empty: show TOP discarded card face (last play/discard) at **72x100 px**, badge = discard count.
- After center reveal hold ends: card tweens **0.3 s** from center to discard pile (slight rotation **+/-8 deg**), then updates top face.
- Hand discards (e.g. BREAK effect): same fly-to-discard from hand slot.
- Marker is intentionally more open/empty than the draw marker.

## Opponent (optional same pass)
- Opponent draw not required if shared/no enemy deck UI; if enemy hand grows from draws, fly from a small top-center offscreen or from player deck if shared rules.
- **This prototype uses player deck only; opponent hand size changes without separate enemy deck pile unless Engineering adds one.**

### HP bars
- Replace numeric-only HP with bar under each nameplate.
- Player: above hand / under "You" — bar 200×18 (scaled), fill = current/max.
- Opponent: under "山賊" name — same size.
- Still show small "3/3" text to the right of the bar for precision.
- Frame: hp_bar_frame.png; fill: hp_bar_fill.png clipped by ratio.

### Choice update
- Dodge button: use face of `res://assets/cards/dodge.png` (or assets/cards/dodge.png) as the button art / left icon, not choice_dodge-only. choice_dodge.png can be the chrome frame OR Engineering composites dodge card scaled into left half of 360×192 with "Play DODGE" label.
- Take Hit: use choice_minus_hp.png / choice_take_hit.png with clear -HP icon.

### Center reveal origin
- Player play: tween from played hand-slot position → center (0.15s).
- Opponent play: tween from opponent hand-stack position → center (0.15s).
- Optional thin colored trail: player gold, opponent vermillion, so origin is obvious.
