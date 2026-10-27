# World risk view audit, 2026-10-22

The product goal is to see the map's danger shapes while running and choose a way
around them. Quest navigation is not a feature of this addon. The experimental
renderer borrows the client's waypoint projection only to measure screen anchors.

## Fixed in 0.3.0-dev9

- **Startup stopped itself.** In the Beta client, selecting the temporary waypoint
  clears a tracked quest. Dev8 compared the resulting nil/empty quest to the saved
  quest and treated its own write as a takeover. Native reproduction used quest
  1505. Dev9 stores the owned tracking state separately from the restoration target.
  Native preview starts and stop restores 1505 with no waypoint or user-tracking flag.
- **Cleanup after partial setter failure could lose the previous target.** The
  cleanup path now accounts for a setter writing before throwing, while rejecting
  foreign quests and waypoints. Automated regressions cover these paths. A native
  external takeover to existing quest 772 was preserved without the temporary point.
- **Failed restoration retried every frame.** Retries are now spaced 250 ms apart;
  status includes the captured restoration error. Verified automatically, without
  deliberately breaking native setters.
- **One-yard motion guard rejected normal running at 60 FPS.** A seven-point batch
  needs fourteen updates. In an independent camera simulation at seven yards/sec,
  dev8 rejected every batch before validation. Dev9 permits two yards, retaining
  both four-pixel validation limits. The simulation passes; the native test below
  shows that this change alone does not make the moving view usable.
- **Replay containment was always false.** Its occupancy table was empty after
  moving the shape. Exact rectangle containment now detects entry while preserving
  gaps; the indicator explicitly says `Inside replay area`. Automated coverage only.

## Dev9 failure: continuous movement

A short local run was tested at an observed 60 FPS in Beta. The contour disappeared
during the movement and returned after stopping. Status after the mixed run showed:

```
attempts 700; accepted 675; rejected 24; 4.2 accepted/s
clamped=21, drift=2, holdout=1; accepted while moving 0
```

An attempt was in progress. Accepted-while-moving counts batches with more than a
quarter yard of displacement; it does not measure continuous running. Most accepted
batches here were stationary, and this is a failed native running test.

The dev9 method measures seven points at different times. A moving camera can
invalidate the fit even with a stable orientation. Prioritize testing a projection
method that compensates for the player's displacement during each sample, with
independent moving-camera validation. This is a proposed investigation, not a
verified solution at that stage. See the subsequent dev10 result below. Increasing error thresholds or retaining old contours would
obscure incorrect placement and is not recommended.

At 30 FPS, fourteen updates also exceed the fixed 350 ms timeout. A shorter or
different sampling method is needed before promising low-FPS support.

## Dev10: compensate movement during sampling

Each screen measurement now records its point relative to the player at that
measurement. Four rebased source corners fit a homography; two independent spatial
holdouts and the repeated anchor check the result. The repeat check compares its
predicted end-position projection with the native measurement. Raw screen motion
is no longer confused with error. Four-pixel error limits, two-yard movement guard,
two-update settling and 350 ms timeout remain unchanged. The mask is rendered at
the latest player position; containment and distance are recomputed there too.
Transient holdout/drift failures retry the visible reference before an offscreen
search. A successful restoration also clears its retry timer correctly.

An initial dev10 short run at 60 FPS accepted five moving batches but briefly hid
the contour at movement start while the camera adjusted. The source was then
updated to retry visible references after a validation failure. The final client
test reported:

```
attempts 421; accepted 418; rejected 2; 4.3 accepted/s
holdout=2; accepted while moving 9
moving max raw 15.1 px; compensated 0.6 px
```

An attempt was in progress. This mixed stationary/running rate is not a continuous
running rate. It establishes that the corrected method can pass independent checks
while running in Forever, including motion far beyond the former raw four-pixel
limit. It does not establish uninterrupted visibility at every camera angle. A
native screenshot shows the contour while the character is in a running pose;
later screenshots show its changed projection after the short movement. The
inside replay indicator was also observed before the final reload. All movement
was local; there was no travel to a quest target or a distant real risk boundary.

Lua 5.1 and LuaJIT each pass 200 checks, including an independent moving camera,
sideways/diagonal motion, end-position rendering, degenerate source rejection and
unchanged validation of camera drift. Both installed links still target source.
Native evidence: `../artifacts/world-dev10-motion-20261022/` relative to repo root.
Replay was stopped, the temporary waypoint released and prior FPS values restored.

## Visual limitations

The renderer remains a UI overlay without depth occlusion; a contour can cover a
tent or be visible through it. Shallow or offscreen references can hide the view.
Terrain heights and alignment at real danger boundaries remain unverified. The
test used a clearly labelled moved/scaled map shape, not a real danger area here.

## Evidence and verification

Native screenshots and results: `../artifacts/world-dev9-audit-20261022/` relative
to the repository root. The tests used only a short local movement.
Both installed addon junctions point to the working source. No death data was edited.
Lua 5.1 and LuaJIT each passed 197 checks; native startup, stop and external takeover
were checked separately. Combat and actual danger-boundary tests remain outstanding.

The generated [SuperTrack API reference](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua)
allows a nullable quest ID. The specific quest-clearing behavior above was observed
directly in Forever, not inferred from Retail documentation.
