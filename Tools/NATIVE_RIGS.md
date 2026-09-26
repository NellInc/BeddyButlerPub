# Native articulated Butlers

`node Tools/bake_native_rigs.cjs` samples the approved shared website skeleton into three asset-catalog datasets. No browser or GIF decoder is used by the app. Each dataset contains a four-float little-endian header (columns, rows, frame count, seconds per cycle), followed by normalized bottom-up XY positions for 120 frames. The grid is sampled at 20 source pixels, suitable for the app's small portraits. The three datasets add approximately 9.5 MB, which the asset catalog stores uncompressed.

`ButlerArticulatedMotion` validates and caches each dataset once, interpolates adjacent frames at the existing SpriteKit display cadence, and applies the result through `SKWarpGeometryGrid`. Existing fit/upper-body sizing, visibility pausing and texture filtering remain. Reduced Motion and zero intensity remove the warp and show the intact original artwork. Missing or malformed data falls back to the previous rigid choreography. Native intensity is capped at the approved full movement to avoid exaggerated mesh distortion.

The Shy face/glove contact restriction is inherited from the source skeleton. These are deformations of flat artwork, not newly separated layers. After tuning the shared JS skeleton, regenerate the datasets and run the native rig tests; the binaries are not updated automatically during app builds.

## Verification
The native build and all 80 tests passed on 7 September 2026. Tests load all three packaged datasets, check loop closure, 121 finite poses, zero-intensity identity, Reduced Motion restoration and changing nonblank SpriteKit-rendered images. Both captured poses of each character are written to `/tmp/beddy-native-{personality}-{0,1}.png`; the second poses were visually inspected.

SpriteKit's default recursive subdivision crashed in `add_subdivs` with this already-dense grid. Production nodes now explicitly use `subdivisionLevels = 0`, and the renderer tests exercise this fix with actual GPU readback. Earlier blank scene snapshots did not constitute rendering evidence. The passing tests use sprite readback and assert nonblank, distinct output.

Local source/build only. No installed app replacement or release was performed.
