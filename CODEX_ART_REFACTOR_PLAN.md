# Codex Art & Rendering Refactor Plan

Repository: `mseppae/hex_pixel_demo`

## Purpose

Refactor the rendering, sprite, and animation architecture before investing further in final artwork. Existing dimensions began as learning-project choices and should not be treated as permanent constraints. Preserve the project's data-driven design and keep the Odin implementation understandable.

## Target specification

- Virtual/internal resolution: **320×180 (16:9)**.
- Pixel-art rendering with **nearest-neighbor filtering**.
- Prefer **integer display scaling** where practical.
- Standard humanoids: approximately **32px-class artwork**; a 32×32 frame may contain ~26–30 px of visible character height.
- Small/large creatures, weapons, effects, and bosses must not be forced into 32×32 frames.
- Retain **six directional views**.
- Decouple world/hex geometry from sprite dimensions.
- Render characters from an explicit **ground/feet anchor**, not texture-center assumptions.
- Support **variable animation frame counts and playback rates**.
- Support **variable frame/canvas dimensions** and data-driven sheet/atlas layouts.

These are architectural/art-direction targets, not instructions to scatter hard-coded constants through the codebase.

## 1. Inspect before changing

Before implementation, audit the complete repository and identify how rendering, virtual resolution, window scaling, camera, hex geometry, asset generation/loading, sprite sheets, animation state, creature definitions, and UI currently work. Find every assumption tied to the current screen dimensions, sprite dimensions, sheet layout, animation count, or sprite positioning. Understand the relationship between `art_source` and generated assets.

Preserve existing good abstractions. Do not mechanically implement structures suggested here when the existing Odin architecture has a cleaner representation.

## 2. Virtual resolution and scaling

Adopt **320×180** as the intended logical pixel-art canvas unless repository inspection exposes a compelling problem. Desired exact scale examples are 1280×720 = 4×, 1920×1080 = 6×, 2560×1440 = 8×, and 3840×2160 = 12×.

Preserve 16:9 aspect ratio, use nearest-neighbor sampling, and define a sensible policy for non-integer-sized windows. The logical rendering resolution must not accidentally redefine world-space or hex-grid geometry.

## 3. Decouple art from gameplay geometry

A creature image's dimensions must not determine hex dimensions, logical position, collision, movement, occupancy, selection, or targeting. A goblin, human, rat, ogre, and boss should be able to occupy the same logical hex while using different image dimensions.

## 4. Ground anchors

Introduce or formalize per-sprite/per-creature rendering anchors. Character sprites should normally use a feet/ground anchor, conceptually such as:

    frame_size: [32, 32]
    anchor:     [16, 28]

Use whatever representation best matches the existing code. Heads, ears, weapons, shadows, and attack poses should be free to extend outside a hex without changing the creature's world position.

## 5. Variable sprite sizes

Do not introduce a global 32×32 requirement. Treat ~32 px as an artistic scale for ordinary humanoids, not an engine limit. Approximate visible-height guidance:

    small creature      ~12–24 px
    goblin              ~24–28 px
    typical humanoid    ~26–30 px
    large creature      ~36–48+ px
    bosses              as required

A goblin might use 32×32 frames while an ogre uses 48×48. Asset metadata and rendering must support this cleanly.

## 6. Animation model

Remove assumptions that each state has one frame or that all animations have equal frame counts. Support independently configured animation sequences, timing/FPS, looping behavior, and direction. Example art budgets—not required constants—are idle 2–4 frames, walk 4–6, attack 4–8, hurt 2–3, and death 5–8.

Runtime animation selection should conceptually resolve **state + direction + frame**. Sheet coordinates should remain asset data, not gameplay logic.

## 7. Six-direction support

Retain six-direction animation, which naturally matches the hex game. Direction ordering must be explicit and documented. Ensure variable-length animations work independently for all six directions.

## 8. Asset layout and generation

Do not require every creature to use one rigid sprite-sheet format. Keep sheets/atlases data-driven so physical packing can change without gameplay changes. If the current generated-sheet approach remains useful, keep it, but centralize dimensions/layout assumptions in metadata or generation code rather than runtime code.

Audit `art_source` and preserve a clean source-art → generated-asset workflow.

## 9. Pixel-perfect rendering

Audit the complete rendering path for nearest-neighbor sampling, stable integer pixel placement, accidental bilinear filtering, subpixel sprite movement, camera-induced shimmer, and scaling artifacts. World/simulation coordinates may remain fractional where appropriate; choose explicitly where visual snapping occurs rather than corrupting simulation coordinates for rendering convenience.

## 10. Camera and battlefield visibility

320×180 changes the visible battlefield. Review camera framing/zoom, hex dimensions, visible hex count, UI placement, selection and movement indicators, and screen-edge behavior. Do not blindly shrink tactical visibility. Camera/world presentation and art resolution should remain separable concerns.

## 11. UI

Audit assumptions tied to the old resolution. Keep UI crisp and readable at 320×180. Do not perform a broad UI redesign unless required for correctness; document visual improvements that should be handled later.

## 12. Incremental migration

Do **not** regenerate or migrate all art during this refactor. Existing assets may temporarily coexist with the generalized system. Prefer backward-compatible defaults where they remain simple, but do not preserve bad architectural assumptions merely for compatibility in this small learning project.

The first visual validation scene should contain the existing terrain/environment, player character, one goblin, and relevant shadows/selection indicators.

## 13. Goblin showcase target

Prepare the architecture for a new goblin using approximately 32×32 frames, a strong readable silhouette, high contrast against sandy/earth terrain, clear ears/head and weapon, separated skin/clothing color masses, a ground anchor, six directions, and multi-frame animations.

Do not fabricate final production art simply to finish the refactor. Placeholder/test frames are acceptable for architectural validation. Final art will be iterated separately after the rendering model is proven.

## 14. Keep the project educational

This remains an Odin/game-development learning project. Avoid unnecessary abstraction and enterprise-style architecture. Prefer straightforward Odin, explicit data, small understandable structures, clear ownership, simple metadata, and comments explaining non-obvious rendering/math decisions.

## 15. Documentation

Update the most appropriate existing documentation (`README`, `AGENTS.md`, `CLAUDE.md`, or another development document) rather than creating redundant documentation. Cover virtual resolution, display scaling, sprite coordinates and anchors, expected art scale, animation metadata, six-direction ordering, atlas/sheet conventions, adding creatures/animations, and legacy-vs-new asset behavior.

## 16. Validation checklist

Before declaring the refactor complete, verify:

1. Project builds successfully.
2. Existing gameplay still works.
3. Hex movement/selection is unaffected by sprite dimensions.
4. A sprite larger than its hex renders correctly.
5. Creatures with different frame sizes render together correctly.
6. Ground anchors align those creatures correctly to their hexes.
7. Variable-length animation playback works.
8. Six directions work with variable-length animations.
9. Non-looping animations complete correctly.
10. Nearest-neighbor output remains crisp.
11. Camera movement does not introduce obvious sprite shimmer.
12. 320×180 scales correctly to common 16:9 window sizes.
13. Legacy assets either continue working or their migration is clearly documented.

## 17. Suggested implementation sequence

1. Audit repository and report relevant current assumptions.
2. Write a concise implementation plan based on the actual code.
3. Refactor virtual-resolution/scaling handling.
4. Decouple render dimensions from world/hex geometry.
5. Add/generalize sprite anchors.
6. Generalize frame dimensions and atlas metadata.
7. Generalize animation frame counts/timing.
8. Validate six-direction animation selection.
9. Adapt camera/UI assumptions.
10. Add a minimal showcase/test creature configuration.
11. Build/run/test.
12. Update documentation.
13. Summarize changes, trade-offs, and remaining art migration work.

Keep changes logically separated and commits reviewable when appropriate.

## 18. Do not overfit to this document

This document specifies desired behavior and art-pipeline goals, not necessarily the implementation. If inspection shows that 320×180 causes a meaningful problem, the renderer already has a better abstraction, frame dimensions are already variable, another metadata representation better matches the code, or a proposed change is unnecessary, explain the finding and adapt the implementation.

Do not change good code solely to make it resemble examples in this brief.

## Definition of done

The engine can cleanly render a 320×180 pixel-art scene containing creatures of different sprite dimensions, aligned to hexes through ground anchors, using six-direction variable-length animations, with crisp nearest-neighbor presentation and without sprite dimensions leaking into gameplay/world geometry.

At that point, stop the broad refactor. The next phase is **art production and visual iteration**, beginning with the player and goblin in one representative gameplay scene.
