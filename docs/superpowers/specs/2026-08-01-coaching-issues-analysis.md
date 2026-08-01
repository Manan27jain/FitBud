# AI Coaching — Issue Analysis and Fix Design

**Date:** 2026-08-01
**Status:** Analysis approved for implementation
**Follows:** `2026-08-01-ai-coaching-design.md` (the shipped implementation this analyses)

The athlete tested the coaching on the simulator and reported: no speech, a "ping-pong"
sound per message, and a message overlay that covers the effort dial rather than sitting
beneath it. He also asked for motivation when the data says he is struggling. Every symptom
was reproduced and traced to code before this document was written.

---

## 1. Errors found, in order of severity

### E1 — Speech is structurally impossible on the simulator

`Support/CoachSpeaking.swift:21-31`. `canBeHeard` returns true only for Bluetooth, AirPlay
or wired headphone routes, and `speak()` returns at its first guard when false. The
simulator's audio route is the Mac's speakers, reported as the built-in speaker — so the
guard fails and **no code path on the simulator can ever produce speech**. Nothing is broken
at runtime; the design decision that protects a real run (never shout into wind at
9 min/km) also makes the feature untestable and *appear* broken anywhere without paired
headphones.

**Fix:** compile-time override — `#if targetEnvironment(simulator)` makes `canBeHeard` true
there, since the "speaker" is the Mac's, which is exactly where a developer wants to hear
it. Real-device behaviour is unchanged.

### E2 — The athlete's music stays ducked forever after the first spoken cue

`Support/CoachSpeaking.swift:36-39`. `speak()` activates the audio session with
`.duckOthers`, and **nothing ever deactivates it**. On a real run with AirPods and music,
the first cue lowers the music volume and it never comes back up — for the rest of the run,
every run. Found during this analysis rather than reported, because speech has never yet
run outside a test bundle.

**Fix:** make the speaker its own `AVSpeechSynthesizerDelegate`; on `didFinish`/`didCancel`,
deactivate the session with `.notifyOthersOnDeactivation` — guarded on
`!synthesizer.isSpeaking`, so a cue that replaces another mid-utterance cannot deactivate
the session under the new speech.

### E3 — The "ping-pong" is the haptic, and every cue plays the same one

`UI/WorkoutSessionModel.swift`, `present()`: every coach message plays
`haptics.play(.splitCompleted)` — `WKHapticType.notification`, which the simulator renders
as the two-tone sound heard. With speech silent (E1), the haptic was the only feedback, so
it dominated. Cues also have no haptic identity: a drift warning, a milestone and the
opening line all buzz identically, where the existing vocabulary already distinguishes
splits from phase changes from completion.

**Fix:** a dedicated `coachCue` haptic (`WKHapticType.directionDown` — distinct from all
five in use), and keep speech as the primary channel now that E1 makes it audible.

### E4 — The message covers the dial; the athlete wants it beneath

`UI/CoachMessageView.swift`: a full-screen `ZStack` with 55% black dims the whole page and
sits over the ring. The original spec argued this was safe because the zone wash reads
through — true but moot: the product owner has seen it and wants the dial visible with the
message **below** it. The centre of the ring cannot hold a sentence (the clear chord is
~82pt), so *below the dial* is the only placement that keeps both fully visible.

**Fix:** rebuild `EffortPage` as a layout where an active cue shrinks the ring (~72%,
sprung animation) and the message slides into the freed band beneath it: a small "COACH"
eyebrow in the zone colour, then the message in SF Rounded semibold, up to three lines,
centred, no card, no dimming. Tap to dismiss and the 6-second auto-dismiss unchanged. The
needle, scale and countdown remain visible the whole time — strictly better than the
overlay on the design's own safety argument.

### E5 — The coach cannot see struggle, so it cannot respond to it

Three gaps compound:

1. **No data.** `WorkoutState` carries only the whole-run `averagePaceSecPerKm`. Nothing
   knows the *recent* pace, so a fade — the athlete slowing under fatigue — is invisible to
   every layer.
2. **No trigger.** `CueTrigger` covers zones, splits, distance, time and milestones. There
   is no vocabulary for "struggling", so even a perfectly-briefed LLM cannot write a rule
   that fires on it.
3. **No prompt.** The live walk-break call sends splits and zone time but never asks the
   model to assess whether the athlete is fading, so its replies are status-shaped rather
   than coach-shaped.

**Fix, in three matched parts:**

- `WorkoutEngine` keeps a rolling window of (elapsed, distance) samples from **run phases
  only** — walk breaks would read as catastrophic fades — cleared on each phase change, and
  publishes `recentPaceSecPerKm` (window span ≥ 45s) on `WorkoutState`. Pure, tested.
- A new trigger `paceFading(percentSlower:sustainedSec:)`: recent pace slower than the
  session average by the given percentage, sustained, only after 1 km (early GPS noise),
  never during a walk. Allowed `.immediate` — encouragement half a lap late is not
  encouragement — extending `mayBeImmediate` to exactly this one additional case. The
  default bundle gains a seventh rule so struggle coverage survives offline.
- The brief schema and system prompt teach the model the new trigger and ask for one
  motivation rule; the live-cue prompt gains the athlete's recent-vs-average pace and an
  explicit instruction: *if the splits show fading, respond with specific encouragement.*

### E6 — Demo cannot demonstrate any of it

`Support/DemoWorkoutRecorder.swift`: the scripted pace is a constant 9:00/km, so a fade
trigger could never fire in the demo, and (pre-E1) speech could not be heard. **Fix:** a
scripted fade window — pace drops ~25% for a stretch mid-sweep, then recovers — so the
struggle cue is visible and audible on the simulator.

## 2. Known limitations recorded previously, unchanged by this work

- At the demo's 20× time compression the 45s urgent floor compresses to 2.25s, so a
  sustained drift re-fires faster than the 6s display window and reads as a persistent
  banner. Demo-only; real time is unaffected.
- The 12-word cap is a proxy for pixel width; twelve unusually long words can still shrink
  to the scale floor. Closing it properly needs text measurement.
- Switching provider in Settings takes effect at next launch (snapshot at wire-up). Latent
  until Gemini exists.

## 3. Improvements toward the coach-buddy goal, beyond this fix round

Ordered by value per effort; none are in this round's scope:

1. **Wire real recovery data** — `CoachContextBuilder` already has nil-safe slots for
   sleep, resting HR and HRV; a HealthKit read makes every brief recovery-aware ("you
   slept 5 hours; today stays gentle").
2. **Memory between runs** — persist each `WorkoutAnalysis` and feed the last one into the
   next brief, so Tuesday's coach remembers Sunday's fade.
3. **Zone-crossing haptics with hysteresis** — drift feedback without looking, deferred
   from the original spec until real-run data exists to tune it.
4. **Race-day mode** — a distinct brief for 27 September: no experiments, 5:1 discipline,
   HR-capped first 5 km, and a coach that talks the athlete out of the fast start.
5. **Post-run one-tap feedback** ("felt easy / okay / hard") — one honest label per run
   makes both the analysis and the next brief materially better.

## 4. Implementation order

| Task | Scope | Verification |
|---|---|---|
| A | E1 + E2 + E3 — speech audible on simulator, session deactivation, coach haptic | Speech heard on simulator; delegate fires; suite green |
| B | E4 — below-dial message presentation | Screenshots: ring visible + message beneath, at multiple zones |
| C | E5 + E6 — rolling pace, `paceFading`, bundle + schema + prompts, demo fade | Engine tests; fade cue seen and heard in demo |
| D | End-to-end demo pass + final whole-branch review (subsumes the one interrupted earlier) | Full run-through with screenshots |

Suite currently 177; C adds engine and decoding tests. `HealthKitWorkoutRecorder` and
`WorkoutRecording` remain untouched, as ever.

---

## 5. Follow-up round: navigation and app icon (2026-08-02)

### E7 — Starting a session from the Sessions list showed nothing until you tapped back

`UI/RootView.swift` wrapped a **single** `NavigationStack` around a `switch model.phase`.
`HomeView` was that stack's *root* when idle, and it pushes `SessionListView` on top of it.
Tapping a session called `start(...)`, setting `phase = .running`, which swapped the stack's
**root** from `HomeView` to `LiveWorkoutView` — while `SessionListView` remained pushed
above it. The root changed underneath the pushed view, so the athlete kept looking at the
session list while a workout recorded invisibly behind it. Tapping back popped the pushed
view and revealed the workout, which is exactly the reported symptom.

**Fix:** move the `NavigationStack` inside each switch branch, so every phase owns its own
stack. A phase change then destroys the entire stack — pushed views included — rather than
swapping a root beneath them.

A programmatic `NavigationPath` was rejected: `HomeView`'s links are closure-based
`NavigationLink { } label: { }`, which never route through a path, so clearing one could not
pop them.

Verified on the simulator: tapping "Easy run" from the Sessions list lands directly on the
Effort page with no back tap. The five live-page titles still render (each branch has a
stack), `LiveWorkoutView` still has no back button, and the pushed views from Home still do.

### E8 — No app icon

`logo/logo.png` (1254×1254, no alpha) resized to the single 1024×1024 universal slot the
`AppIcon.appiconset` expects. watchOS rejects icons with an alpha channel; the source has
none and the generated file was checked. The 1.2 MB source stays out of the repo — only the
generated icon lives in the asset catalog.
