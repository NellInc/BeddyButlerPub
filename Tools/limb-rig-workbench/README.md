# Insistent limb-rig experiment

Unlinked local prototype. No production app rig, homepage, copy, or artwork asset changed.

Thirty-two hierarchical joints: body, chest, neck, head, two shoulders, two elbows, two wrists, eight visible digit roots, eight knuckles, and two hip/knee/ankle chains. A 32 by 40 textured mesh with sixfold local hand refinement uses normalized spatial skin weights. The face remains rigid. Chest breathing accompanies a small pelvic weight shift. Two-bone inverse kinematics bends the knees to reach moving ankles; a slight heel lift pivots each shoe around a fixed toe contact. Digit motion is deliberately restrained and slightly staggered over an eight-second loop. Controls provide motion strength, deterministic pose scrubbing, a bone overlay and exact rest pose. Reduced Motion starts paused; hidden tabs skip rendering.

Run `node Tools/limb-rig-workbench/test.cjs` from the repository root. Tests check identity, normalized weights, connected finite joint transforms across 121 poses, loop continuity and fixed toe contacts. These are geometry checks, not artistic acceptance.

Visual review: original and articulated pose inspected side by side in the local browser. This is flat-image skinning, not separated production limb artwork. Extreme bends can distort cuffs, clothing and overlapping arms; hidden body surfaces cannot be revealed. Next acceptance is Nell's motion review before authoring separated layers or native integration. Existing native rigid-sprite tests remain unchanged.

Full-body pose visually inspected after leg integration. Flat mesh still shows fine triangulation seams, so this remains an experimental preview rather than a production-quality renderer.

## Three-character rigs
`characters.js` now defines Shy and Zombie joint coordinates, hand regions, fingers, leg chains, head bounds and personality timing. Both use the articulated mesh renderer, not static images. Shy uses restrained hand-to-mouth motion; Zombie uses slower claw and forearm movement. Original aspect ratios are retained. The gallery embeds all three running rigs.

Run the geometry checks with `node Tools/limb-rig-workbench/test.cjs shy`, `node Tools/limb-rig-workbench/test.cjs insistent`, and `node Tools/limb-rig-workbench/test.cjs zombie`. All three passed identity, normalized weights, 121 connected finite poses, loop continuity and toe-contact checks. Browser screenshots showed changed poses for all three characters. Mesh seams and flat-image occlusion limitations remain experimental.

## Renderer and yawn-contact repair
Rendering now uses one indexed WebGL mesh draw rather than thousands of Canvas clips. A uniform shared-vertex mesh removes the adaptive T-junctions. Animation phase uses unrounded wall-clock progression on requestAnimationFrame; paused/hidden periods reset timing. Canvas remains a compatibility fallback.
Shy's overlapping raised glove and face move as one rigid contact region, with a smooth transition at the cuff/neck and arm IK maintaining wrist contact. Independent raised-finger deformation is intentionally disabled for this flattened overlapping source, pending separated artwork. Other hand and body articulation remains. Close-up browser checks at two poses verified the glove silhouette and face, and the canvas reported the WebGL renderer. Geometry tests cover the rigid contact region.

## Website integration (7 September 2026)
The homepage now uses all three approved rigs in its existing personality cards. The canonical implementation lives in `Website/assets/avatar-rig/`; this experiment loads that same implementation. Earlier prototype-only statements above describe historical stages.

The website loader keeps the original accessible images until the GPU renderer is ready, restores them when Reduced Motion is enabled or the GPU context is lost, and pauses offscreen/hidden animation. Copy and sample controls are unchanged. The embedded renderer shares the site's dark colour scheme to retain transparent card backgrounds.

Verification: all three geometry suites, website validation, sample tests and the new `Tools/test_website_avatars.cjs` loader lifecycle tests pass. Browser inspection confirmed all three ready states and changing poses on the homepage with the original dark backgrounds. Local preview only, not deployed. The native SpriteKit app is unchanged; equivalent native mesh integration and native visual acceptance remain separate work.

## Native integration
The approved motion is now baked into native SpriteKit mesh datasets by `Tools/bake_native_rigs.cjs`. See `Tools/NATIVE_RIGS.md` for the playback contract and verified native rendering. This supersedes the earlier native-app-unchanged status above.
