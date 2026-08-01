# Device checklist

Everything below has been verified in the Apple Watch Series 10 (46mm) watchOS 11.2 simulator:
build, tests, navigation, the live workout's five pages, pause/resume, the summary's zone
breakdown and splits, and the full record → save → home-screen-reload loop (see
`.superpowers/sdd/2026-08-01-workout-ui-redesign/task-19-report.md`). The simulator has no heart
rate sensor, no GPS, no Taptic Engine, and no meaningful HealthKit history — so the items below
have not been, and cannot be, verified there. They need one run on a real wrist.

- [ ] **Heart rate reaching the ring.** `EffortPage`/`EffortRingView` and `ZonesPage` read
  `state.heartRate` from `HealthKitWorkoutRecorder`'s live `HKLiveWorkoutBuilder` statistics
  (`FitBud Watch App/Health/HealthKitWorkoutRecorder.swift`). Confirm a real BPM value appears
  within the first 5–15 seconds of a run (the code's own comment on `startTicking()` names this
  window), that the needle and ring colour track actual effort through at least one zone
  transition, and that "WARMING UP" clears once heart rate crosses 133 bpm.

- [ ] **Split haptics at each kilometre.** `SplitDetector` fires `.splitCompleted` →
  `WKHapticType.notification` at each completed km (`FitBud Watch App/Support/HapticPlaying.swift`).
  Confirm the buzz is felt at real, GPS-measured kilometre boundaries during an outdoor run — the
  simulator can only prove the *logic* fires on synthetic distance deltas, not that real
  distance accumulation lines up with a real kilometre.

- [ ] **Run/walk haptics at interval boundaries.** `RunWalkCycler`'s phase changes map to
  `.startRunning` (`WKHapticType.start`) and `.startWalking` (`WKHapticType.stop`). Confirm both
  are felt, and felt as *distinct* patterns from each other and from the split buzz, during a
  run/walk session (e.g. "Long run 4:1" from `SessionListView`, or a plan day with `runWalk` set).

- [ ] **Block haptics during a structured session.** `.blockChanged` plays `WKHapticType.directionUp`,
  chosen specifically to read differently from the split and run/walk pair through a sleeve (see
  the comment in `HapticPlaying.swift`). Confirm this on a plan day with warmup/work/cooldown
  blocks — the first is the week-3 tempo/interval session once the block starts — and confirm it
  is actually distinguishable by feel from the other two haptics, not just distinct in code.

- [ ] **Always-on dimmed readability.** Confirm every live page (Controls, Effort, Zones,
  Metrics, Splits) stays legible when the wrist drops and the display switches to the dimmed
  always-on state: the elapsed-time yellow, the five zone colours, and the effort ring's
  inactive-zone opacity (`Theme.inactiveZoneOpacity = 0.22`) all need to survive dimming without
  the screen going effectively blank or the zone scale disappearing into the dimmed background.

- [ ] **The workout appearing in Apple Fitness.** `HealthKitWorkoutRecorder.end(splits:)` calls
  `builder.finishWorkout()`, which saves an `HKWorkout` of `activityType = .running`,
  `locationType = .outdoor`. Confirm a completed run shows up in the Fitness app (or Health app)
  on the paired iPhone shortly after ending, with distance, duration and average heart rate
  matching what the watch's own summary showed.

- [ ] **The history probe's real answer to how far back watchOS keeps health data.**
  `HistoryProbeView` (reachable from the home screen's "Health history probe" link) queries
  resting HR, HRV (SDNN) and VO2 max via `HealthHistoryProbe` and reports sample count, oldest
  sample date, and day span for each. This is spec §12.1's open question
  (`docs/superpowers/specs/2026-07-31-fitbud-ai-coach-design.md`, section 12) — the simulator has
  no data to report and always answers "0 samples", so it has never actually been resolved.
  Run the probe on a device with real history and record what it reports: if the watch's local
  store turns out to be shallow, `ReadinessMonitor` (Stage 4) must build its own rolling
  baselines from data FitBud accumulates itself rather than querying watchOS history.
