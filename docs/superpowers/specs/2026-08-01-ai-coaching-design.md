# FitBud — AI Coaching on the Effort Screen

**Date:** 2026-08-01
**Status:** Approved
**Builds on:** `2026-07-31-fitbud-ai-coach-design.md` §6.1 (the cue bundle) and
`2026-08-01-workout-ui-redesign-design.md` (the Effort page this attaches to)

---

## 1. Goal

Put a coach's voice into the run. Before it starts, an LLM reads the athlete's plan, recent
runs and overnight recovery and writes the session's coaching. During the run a local engine
delivers it, and at walk breaks the model gets a second look at how the run is actually going.
Afterwards it says what happened.

The athlete's plan requires 80% of running in Z1–Z2; every run in his recorded history sat at
85–92% of max heart rate. The ring already makes that visible. This makes it *audible*, which
matters because a runner's eyes are mostly on the road.

## 2. Architecture: three moments

Only one of these sits on the critical path of a run, and it has a fallback.

| Moment | Call | Returns | On failure |
|---|---|---|---|
| Tap Start | `brief(context:)` | `SessionBrief` — an opening line plus `[CueRule]` | Built-in bundle derived from the plan's zone table. **The run is never blocked.** |
| During | *none* | — | — |
| Walk break | `liveCue(context:)`, 4s timeout | one `String` | Speaks the queued bundled cue instead |
| After | `analyze(workout:context:)` | `WorkoutAnalysis` | Summary renders without it |

The during-run path is deliberately empty of network calls. A cue that arrives four seconds
after the drift it describes is worse than no cue, and the watch radio is unreliable at pace.
That constraint is what the cue bundle exists to satisfy.

Walk breaks are the exception because they are genuinely not time-critical: the athlete is
already easing off for sixty seconds, the phone is in a pocket, and a two-second response
lands comfortably inside the window. This is what lets the coach say *"your last split was
8:12, forty seconds slower than the one before"* — a thing no pre-written rule can know.

## 3. Interfaces

```swift
@MainActor
protocol AIProviding {
    var id: ProviderID { get }                     // .openAI | .gemini
    func brief(context: CoachContext) async throws -> SessionBrief
    func liveCue(context: LiveCoachContext) async throws -> String
    func analyze(workout: CompletedWorkout,
                 context: CoachContext) async throws -> WorkoutAnalysis
}

protocol CoachSpeaking {
    /// True only when a Bluetooth or AirPlay route is connected.
    var canBeHeard: Bool { get }
    func speak(_ text: String)
    func stop()
}

/// Pure. No network, no clock, no HealthKit.
protocol CueEvaluating {
    mutating func evaluate(state: WorkoutState, events: [WorkoutEvent]) -> [Cue]
}
```

### Context

`CoachContext` is assembled once at Start and carries what the model needs to be specific
rather than generic:

- today's `PlanDay` — title, target distance, target zone, run/walk ratio, the plan's own notes
- `BlockProgress` — week index, days to race, volume done against planned, `easyShare`
- the last three `HistoricRun`s — distance, pace, average heart rate, zone
- overnight recovery where available — sleep hours, resting HR, HRV, each against its baseline
- the zone table, so the model states real bpm numbers rather than inventing them

`LiveCoachContext` is a much smaller payload sent at a walk break: elapsed, distance, splits so
far, time in each zone, current zone, and which walk break this is.

### The cue bundle

```swift
enum CueTrigger: Equatable, Sendable {
    case zoneAbove(ceiling: String, sustainedSec: TimeInterval)
    case zoneBelow(floor: String, sustainedSec: TimeInterval)
    case splitCompleted(index: Int?)          // nil matches any split
    case distanceReached(km: Double)
    case elapsedReached(minutes: Double)
    case phaseStarted(RunWalkPhase)
    case halfway                              // against the plan day's target distance
    case finalKilometre
}

enum CueUrgency: Equatable, Sendable {
    case immediate        // interrupts, even mid-interval
    case atNextBreak      // queues until the next walk break
}

struct CueRule: Equatable, Sendable, Codable {
    let id: UUID
    let trigger: CueTrigger
    let message: String        // <= 12 words, enforced on decode
    let urgency: CueUrgency
    let repeats: Bool          // false: fires once per workout
}
```

Only `zoneAbove` and `zoneBelow` may be `.immediate`. Everything else queues — a milestone or a
word of encouragement can always wait sixty seconds, and interrupting a hard interval to deliver
one is exactly the behaviour that makes people turn coaching off.

### The default bundle

Not a placeholder — this is what plays whenever the model is unreachable, so it is specified
rather than left to an implementer's judgement. Built from the plan day's target zone, so it is
correct for any session without asking anyone:

| Trigger | Urgency | Repeats | Message |
|---|---|---|---|
| `zoneAbove(ceiling: targetZone, sustainedSec: 30)` | `.immediate` | yes | "Above easy. Ease off and let it come down." |
| `zoneBelow(floor: "Z1", sustainedSec: 60)` | `.atNextBreak` | yes | "You can pick it up a little." |
| `phaseStarted(.walk)` | `.atNextBreak` | yes | "Walk break. Breathe." |
| `splitCompleted(index: nil)` | `.atNextBreak` | yes | "Another kilometre down." |
| `halfway` | `.atNextBreak` | no | "Halfway. Still feeling easy?" |
| `finalKilometre` | `.atNextBreak` | no | "Last kilometre. Finish strong." |

Deliberately plain. Generic encouragement that pretends to be personal is worse than
encouragement that is honestly generic, and this bundle only ever plays when the personal
version could not be fetched.

## 4. Rate limiting

The difference between a coach and a nag, and the reason this logic is pure and tested:

1. **90 seconds minimum** between any two cues.
2. **Urgent cues bypass the queue** but still respect a **45-second floor**, so a heart rate
   flapping across 163 cannot fire repeatedly.
3. **Non-repeating rules fire once** per workout.
4. **At most one cue per walk break**, so a backlog drains one message at a time rather than
   emptying itself into a single sixty-second window.
5. A cue is dropped, not deferred, if its moment has passed — a "halfway" line delivered at 80%
   is worse than silence.

## 5. Display

`CoachMessageView` overlays the Effort page.

It **covers the ring**, and that is safe rather than a compromise: `EffortPage` already sets
`.containerBackground(Theme.pageWash(washTint))`, and that wash tracks the live zone. Green
behind the words still means green, so the safety signal survives the message sitting on top
of it.

It could not live inside the ring in any case. The clear chord at the label's height is about
82pt — measured off a 46mm screenshot, and the reason "Z4 THRESHOLD" had its leading letter
swallowed by the ring's cap during the redesign. "WARMING UP" barely fits. There is no room
for a sentence.

- Slides up from the bottom, full bleed, over the zone wash
- SF Rounded semibold at **20pt**, with `.minimumScaleFactor(0.7)` and **three lines maximum**,
  so a 12-word cue fits at full size and an over-length one shrinks rather than truncating
  mid-sentence. White on the wash, which is dark enough at every zone tint to carry it.
- A haptic on arrival, using the existing `WorkoutHaptic` vocabulary
- Auto-dismisses after 6 seconds, or immediately on tap
- The crown still pages while a message is up — the athlete is never trapped behind it

## 6. Speech

`AVSpeechSynthesizer`, behind `CoachSpeaking`.

**It speaks only when a Bluetooth or AirPlay route is connected**, checked via
`AVAudioSession.currentRoute.outputs`. The Series 10's own speaker cannot compete with wind and
road noise at 9 min/km; a coach that shouts into that is a coach the athlete stops trusting.
With nothing paired the message is still shown and still buzzes, silently.

- Ducks other audio (`.duckOthers`) rather than stopping it
- Slightly below default rate — clearer at effort
- Toggleable, defaulting **on**, since the athlete usually runs with AirPods
- Never speaks two messages over each other: a new one stops the old

## 7. Configuration

The key lives in `Secrets.xcconfig`, which `.gitignore` already covers:

```
OPENAI_API_KEY = sk-...
GEMINI_API_KEY =
```

surfaced through the existing `Support/Info.plist` as `$(OPENAI_API_KEY)` and read with
`Bundle.main.object(forInfoDictionaryKey:)`.

**A key in an app bundle is readable by anyone holding the bundle.** For a personal, sideloaded,
single-user app that is an acceptable trade and worth stating plainly; it would not be
acceptable for anything distributed. If this app ever leaves this wrist, the key moves behind a
server and this decision must be revisited.

Provider choice is `@AppStorage`-backed and surfaced in a small settings page reached from the
home screen. OpenAI is implemented first; Gemini sits behind the same `AIProviding` seam and
requires no change above it.

## 8. Cost

A small, fast model — the exact identifier is a configuration value to be confirmed at
implementation time rather than hardcoded from memory here.

Per run: one brief (~1200 in / 400 out), roughly seven live cues (~800 in / 40 out each), one
analysis (~1500 in / 250 out) — on the order of **10k tokens**. At four runs a week this is
cents per month, so cost is not a design constraint. Battery is the real budget, and seven short
radio wakes across a 45-minute run with the phone nearby is the reason live calls are confined
to walk breaks.

## 9. Error handling

| Failure | Behaviour |
|---|---|
| No API key configured | AI disabled entirely; the app is the tracker it already is |
| `brief()` fails or times out | Default bundle from the plan's zone table; run starts on time |
| `liveCue()` slow or fails | Queued bundled cue plays; athlete notices nothing |
| Model returns malformed JSON | Bundle rejected wholesale, default used; never partially applied |
| A cue message exceeds 12 words | Rejected on decode rather than truncated mid-sentence |
| `analyze()` fails | Summary renders without it; the run is already saved |
| No Bluetooth route | Text and haptic only, silently |

The governing rule, unchanged from the original spec: **nothing the AI does can prevent a run
from being recorded.**

## 10. Testing

Concentrated on the pure layer, which is where the behaviour lives:

- **Trigger matching** — each `CueTrigger` fires on the state it describes and not otherwise;
  `sustainedSec` genuinely requires duration rather than a single sample crossing a boundary.
- **Rate limiting** — the 90s gap, the 45s urgent floor, once-only rules, one-per-break. Assert
  a synthetic stream of a flapping heart rate produces *one* cue, not twelve.
- **Queue behaviour** — non-urgent cues wait for a break; a stale cue is dropped rather than
  delivered late.
- **Decoding** — a hostile bundle (malformed JSON, 40-word messages, unknown trigger kinds,
  `.immediate` on a non-zone trigger) is rejected without crashing and without partial
  application.
- **Fallback** — with a stubbed failing provider, the default bundle still produces cues.
- `CoachSpeaking` and the network layer sit behind protocols and are faked.

Not unit tested: `AVSpeechSynthesizer` and the HTTP calls themselves. Verified on device.

## 11. Out of scope

- **Plan adaptation.** `adapt()` and the mutation validator (original spec §6.2) remain future
  work. This spec gives the AI a voice, not write access to the training plan.
- **Conversation.** No back-and-forth, no questions to the athlete mid-run.
- **On-device models.** Not viable on watchOS for this.
- **Coaching on the other four pages.** The Effort page is where the athlete looks.

## 12. Open questions

1. **Whether `.immediate` zone cues should also fire during a walk break.** A drift warning
   while walking is almost always noise — the heart rate is falling by design. Leaning toward
   suppressing zone cues entirely during a walk phase, but this wants a real run to settle.
2. **Whether the opening brief should be spoken at the start**, or only shown. Spoken risks
   talking over the first thirty seconds when the athlete is still settling.
