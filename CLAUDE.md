# FitBud

A watchOS-only SwiftUI running-coach app. No iPhone companion — everything
lives on the watch. Built as a personal training tool for a half marathon on
**2026-09-27**.

## Architecture

Single Xcode project, three targets: `FitBud Watch App` (the app),
`FitBud Watch AppTests` (Swift Testing unit tests), `FitBud Watch AppUITests`.
Bundle ID `mj.FitBud.watchkitapp`.

```
FitBud Watch App/
  Models/     Foundation-only data types (HRZone, WorkoutState, Cue, TrainingPlan, ...)
  Engine/     Foundation-only pure logic (WorkoutEngine, CoachEngine, RunWalkCycler, ...)
  Health/     HealthKit integration — see "Do not touch" below
  Coach/      AI provider seam (OpenAI now, Gemini configurable), prompts, settings
  Support/    Speech, haptics, formatting, the demo (scripted) workout recorder
  UI/         SwiftUI views, one file per screen/component
  Resources/  Bundled training-plan JSON, Secrets.plist (gitignored)
```

**`Models/` and `Engine/` import Foundation only, never SwiftUI.** Colors and
fonts for domain types live as extensions in `UI/Theme.swift` (e.g.
`HRZone.color`), not on the model itself. This is what keeps the engine
testable without a UI and is enforced by convention, not the compiler — check
before adding an import.

**Cue-bundle architecture (the reason coaching works with a flaky watch
radio):** an LLM is never in the loop *during* a run. Before a run,
`AIProviding.brief()` returns a `SessionBrief` (opening line + `[CueRule]`).
A local, pure `CoachEngine` evaluates those rules against live `WorkoutState`
every tick, entirely offline. One opportunistic live network call is allowed
during a walk break, since that's the one moment the athlete is resting and a
stall costs nothing. Post-run, `AIProviding.analyze()` gets one more turn for
a written summary. See `docs/superpowers/specs/2026-07-31-fitbud-ai-coach-design.md`
§6 for the full reasoning.

**Training plan overlay seam:** `PlanStore.effectivePlan()` is meant to be
the one place every view reads the plan from, so a future adaptation overlay
(accepted proposals reshaping the remaining block) applies in one place. As
of this writing `WorkoutSessionModel.swift:169,374` and `CoachContext.swift:106`
still call `loadBundled()` directly — harmless while the two are identical,
a real defect the moment they're not. See
`docs/superpowers/specs/2026-08-02-plan-view-and-adaptation-design.md` §12.

## Do not touch

`FitBud Watch App/Health/HealthKitWorkoutRecorder.swift` and
`FitBud Watch App/Health/WorkoutRecording.swift` are the most safety-critical
files in the project — they own the real `HKWorkoutSession` /
`HKLiveWorkoutBuilder` lifecycle. Every plan and every subagent task in this
project's history has treated them as sacrosanct after their Stage 1
hardening. Verify with:

```bash
git diff --stat main -- "FitBud Watch App/Health/HealthKitWorkoutRecorder.swift" \
                        "FitBud Watch App/Health/WorkoutRecording.swift"
```
Expect empty output.

`HealthKitWorkoutRecorder.start()` has a known re-entrancy hazard, guarded
but not eliminated: `recorder.start()` suspends 1–3s inside `beginCollection`
while `WorkoutSessionModel.isStarting` blocks a second *button-driven* call,
but two `start()` calls arriving close enough together outside normal UI
flow (e.g. scripted/rapid taps during simulator testing) can still orphan an
`HKWorkoutSession` — watchOS permits only one active session, so the next
real start hangs indefinitely with no error. The fix is a full simulator
reboot (`xcrun simctl shutdown` + `boot`), not just relaunching the app —
the orphaned session lives at the watchOS daemon level. See the comment
at `WorkoutSessionModel.swift:121-130` for the full mechanism.

**Never edit `FitBud.xcodeproj/project.pbxproj`.** The project uses Xcode 16's
synchronized folder groups (`objectVersion = 77`,
`PBXFileSystemSynchronizedRootGroup`) — new `.swift` files under `FitBud Watch App/`
are picked up automatically, no pbxproj entry needed. `xcodebuild` cosmetically
re-sorts the file on most builds; revert with `git checkout -- FitBud.xcodeproj/project.pbxproj`,
never commit it.

## Commands

Build:
```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" build
```

Test (Swift Testing, 204 tests as of this writing):
```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 \
  | grep -E "✔|✘|error:|\*\* TEST"
```

The simulator (`ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5`, Apple Watch Series 10
46mm, watchOS 11.2) may need booting first: `xcrun simctl boot <id>` — ignore
an "already booted" error. List devices with `xcrun simctl list devices` if
that UDID no longer resolves on this machine.

Driving the simulator's UI for verification: the Simulator's native Crown
accessibility actions and `osascript`'s synthetic clicks are both unreliable
on this watchOS/Simulator combination — clicks can silently fail to register
even on large, obvious targets. Real `CGEvent` mouse-down/up pairs (posted at
`.cghidEventTap`) work reliably; `osascript`-driven `click at {x,y}` does not.
Screenshot after every input and visually confirm the change before issuing
the next one — don't chain blind actions.

## Testing

**Swift Testing only** (`import Testing`, `@Test`, `#expect`). Never XCTest —
`@testable import FitBud_Watch_App` in every test file.

## Secrets

`FitBud Watch App/Resources/Secrets.plist` holds the real OpenAI API key,
read via `Bundle.main.url(forResource:"Secrets", withExtension:"plist")`.
It is gitignored and auto-bundled by the synchronized folder group.
`Secrets.example.plist` (committed) documents the shape with empty values.

**Note:** `.gitignore`'s comment claims keys "ship via a local xcconfig" —
that's stale. The project has no `baseConfigurationReference` and no
`.xcconfig` file; wiring one would require editing `project.pbxproj`, which
is forbidden (see above). `Secrets.plist` is the actual, current mechanism.

Without a real network provider configured, AI coaching falls back to a
curated default cue bundle (`Models/DefaultCueBundle.swift`) and the app
runs fully offline — this fallback is a feature, not a degraded mode.

## Training plan

`FitBud Watch App/Resources/half-2026-09-27.json` — an 8-week block (plus a
2-day calibration bridge, indexed week 0) generated from a real Apple Health
export. Its `rules` block (progression caps, immutable weeks, zone
discipline) is load-bearing: week 4 is an immutable cutback, weekly volume
never rises more than 20% over the last non-cutback week, the long run caps
at 16km before race day. Human-readable version at `docs/TRAINING-PLAN.md`.

## Repo-agnostic conventions

Everything else — scope discipline, verification-before-claiming-done,
skill usage, git safety — follows the user's global instructions. This file
only holds what's specific to FitBud.
