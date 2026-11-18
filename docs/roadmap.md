# Movie Creator roadmap

## Product decisions
- Android-first, portrait-only editing UI. PC mouse compatibility is secondary.
- Offline local project editing; no cloud account or network requirement.
- Godot 4.7.x; GL Compatibility renderer for mobile.
- Editable project data and in-game cutscene runtime will be separate.

## MVP 0.1 (this commit)
- Touch orbit / pinch zoom, mouse orbit / wheel zoom.
- Primitive 3D objects, tap selection, position and rotation nudges.
- Per-object keyed transforms, linear position and shortest-path rotation interpolation.
- Touchable track timeline with key drag and playback/scrubbing.
- Local JSON save/load under user://movie_project.json.

## Next steps
1. In-app Android Storage Access Framework import for GLB/glTF and audio; maintain stable material and skeleton references.
2. Camera cut track and camera preview vs edit-camera separation.
3. Bone/keyframe pose editing; model-specific rig and pivot handling.
4. In-game Godot runtime, scene events, skipping, and game state restoration.
5. Export project archive / import and share-sheet integration; Android build pipeline.
6. Touch accessibility, autosave/history, undo-redo, performance profiling, automated tests.

## Safety and scope
This repository contains a standalone editor. Never modify the SERA or Pocket District repositories to develop this editor.
