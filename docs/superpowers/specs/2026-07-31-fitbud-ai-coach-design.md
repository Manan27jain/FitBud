# FitBud — AI Running Coach for Apple Watch

**Date:** 2026-07-31
**Status:** Approved (architecture + staging)
**Target event:** Half marathon, 2026-09-27 (58 days out)

---

## 1. Goal

A personal running coach that lives on the wrist: it holds the training plan, conducts each
workout, coaches in real time using live heart rate and pace, and rewrites the remaining plan
each week based on measured performance and recovery.

Single user. No accounts, no sharing, no App Store.

**Success criterion:** the athlete reaches the start line on 27 September having trained
consistently, uninjured, and finishes the half marathon running.

## 2. Constraints

| Constraint | Consequence |
|---|---|
| 58 days to race day | Stage 1 must be usable within a week. Feature freeze 2026-09-13. |
| watchOS-only target | No iPhone companion, no WatchConnectivity. The iOS `FitBud` target stays an unused stub. |
| No iOS simulator runtime installed | Build with `-target "FitBud Watch App" -sdk watchsimulator`, not `-scheme`. |
| Watch radio is unreliable mid-run | **No network call may sit on the critical path of a workout.** |
| Personal use | API key ships via gitignored `Secrets.xcconfig`. No auth, no multi-tenancy. |

## 3. Athlete baseline

Derived from an Apple Health export (426,761 records, 26 running workouts, Dec 2024 – Jul 2026).

| Metric | Value |
|---|---|
| Age / sex / weight | 25 / male / 70kg |
| Max HR observed | 207 bpm |
| Resting HR | 60 baseline, 66.5 30-day avg |
| HRV (SDNN) | 52.4ms 30-day avg |
| VO2max | 36.1, rising (+2.2 over 90 days) |
| Longest run ever | 8.01km (2026-07-26) |
| Weekly volume | ~11km, highly inconsistent |
| Avg HR on runs | 175–191 bpm (85–92% of max) |
| Sleep | median 5.5h; 17 of 30 nights under 6h |

Two findings drive the product:

1. **Every run in the athlete's history is at threshold effort.** There is no easy running in
   the data at all. The coach's primary job is enforcing Zone 2 discipline.
2. **Sleep is the binding constraint, not fitness.** Any adaptation logic that ignores sleep
   will progressively overload an already under-recovered athlete.

## 4. Training plan

Generated once, offline, from the health export. The app consumes it; it does not author it.

- Human-readable: `docs/TRAINING-PLAN.md`
- Machine-readable: `Plan/half-2026-09-27.json` — the app's source of truth

Structure: 8 weeks (Mon 2026-08-03 → race Sun 2026-09-27) plus a 2-day calibration bridge.
Volume 16 → 19 → 22 → **17 (cutback)** → 26 → 28 → 24 → 9 + race.
Long run 8 → 10 → 12 → 9 → 14 → **16** → 11 → 21.1.

The JSON carries a `rules` block — sleep gate, recovery gate, progression caps, and an
`immutable` list. These are not documentation; they are the input to the mutation validator
(§6.2) and are enforced in code.

The plan validates against its own rules: every build-week long run rises exactly +2km, and
weekly volume rises 19%/16%/18%/8%, all within the stated 20% cap.

## 5. Architecture

Single watchOS target, organised into modules behind protocols. Nothing above a protocol
boundary needs a watch, a network, or HealthKit to test.

```
        ┌──────────────┐
        │      UI      │  Today · Live · Summary · Plan · Settings
        └──────┬───────┘
    ┌──────────┼────────────┬─────────────┐
┌───▼────┐ ┌───▼─────┐ ┌────▼──────┐ ┌────▼────────┐
│PlanKit │ │ Workout │ │  Coach    │ │  Readiness  │
│        │ │ Engine  │ │  Engine   │ │  Monitor    │
└───┬────┘ └───┬─────┘ └────┬──────┘ └────┬────────┘
    │          │            │             │
    │      ┌───▼────────────▼─────────────▼───┐
    │      │          HealthBridge            │  HealthKit + HKWorkoutSession
    │      └──────────────────────────────────┘
    │
┌───▼──────────┐
│  AIProvider  │  OpenAI | Gemini      (never on a workout's critical path)
└──────────────┘
```

### 5.1 Public interfaces

Defined before implementation. Concrete types are internal.

```swift
protocol PlanProviding {
    func currentPlan() throws -> TrainingPlan
    func session(on date: Date) -> PlanDay?
    func apply(_ mutation: PlanMutation) throws   // throws if the validator rejects
}

protocol HealthReading {
    func readiness(asOf date: Date) async throws -> ReadinessSnapshot
    func recentWorkouts(limit: Int) async throws -> [CompletedWorkout]
    func baseline(for metric: HealthMetric, days: Int) async throws -> Baseline
}

protocol WorkoutRecording {
    func start(_ day: PlanDay) async throws -> AsyncStream<LiveMetrics>
    func pause() async throws
    func resume() async throws
    func end() async throws -> CompletedWorkout
}

protocol CueEvaluating {                       // pure, synchronous, no I/O
    func evaluate(state: WorkoutState, metrics: LiveMetrics) -> [Cue]
}

protocol AIProviding {
    var id: ProviderID { get }                 // .openAI | .gemini
    func brief(_ context: CoachContext) async throws -> SessionBrief
    func analyze(_ workout: CompletedWorkout,
                 context: CoachContext) async throws -> WorkoutAnalysis
    func adapt(_ context: AdaptationContext) async throws -> PlanMutation
}
```

`SessionBrief` carries `[CueRule]` — see §6.1.

### 5.2 Module responsibilities

| Module | Owns | Depends on |
|---|---|---|
| **PlanKit** | Plan model, persistence, mutation application, `MutationValidator` | — |
| **HealthBridge** | HealthKit auth, metric reads, workout session lifecycle | HealthKit |
| **WorkoutEngine** | Segment state machine, run/walk timer, haptics | HealthBridge |
| **CoachEngine** | Cue rule evaluation against live metrics | — (pure) |
| **ReadinessMonitor** | Sleep/recovery gates vs. rolling baselines | HealthBridge, PlanKit |
| **AIProvider** | Prompt construction, HTTP, response decoding | — |
| **UI** | SwiftUI views, navigation | all |

## 6. Two load-bearing decisions

### 6.1 The cue bundle — AI coaching without network during a run

An LLM cannot be in the loop mid-run: the radio is unreliable, round-trips take seconds, and a
cue is worthless if it arrives forty seconds after the pace drift it describes.

So the LLM does not *speak* during the run — it *writes the rules* before it. `brief()` returns
a `SessionBrief` containing `[CueRule]`, each a condition/message pair tailored to today's
session and today's readiness:

```
{ trigger: .hrAboveZoneCeiling(sustainedSec: 30), message: "Above easy. Walk 30s." }
{ trigger: .distanceReached(km: 7),               message: "This is where last week hurt. You're fine." }
{ trigger: .segmentStarting(index: 4),            message: "Last rep. Make it the best one." }
```

`CoachEngine` evaluates these locally against the live metric stream. Network is required only
to *fetch* the bundle, minutes before the run, and its absence is survivable: the engine falls
back to generic zone rules built from the plan's own zone table and the run is unaffected.

This is what lets the coaching be both intelligent and real-time — the intelligence is
front-loaded, the reaction is local.

### 6.2 The mutation validator — the AI proposes, it does not decide

Weekly adaptation is the feature most likely to hurt the athlete. An LLM asked to "adjust the
plan" will cheerfully delete a cutback week because the athlete felt strong, or add volume to a
taper.

`adapt()` therefore returns a `PlanMutation` — a *proposal*. `PlanStore.apply` runs it through
`MutationValidator` against the `rules` block in the plan JSON:

- Week 4 cutback cannot be removed or upgraded
- Weeks 7–8 cannot gain volume or intensity
- Long run cannot exceed 16km before race day
- Weekly volume cannot rise >20% over the last non-cutback week
- Long run cannot rise >2km
- No more than 2 quality sessions per week

A mutation violating any rule is rejected with a reason, and the existing plan stands. The AI
can suggest anything; it can only *do* what the guardrails permit. This is the piece that makes
it safe to put an LLM in charge of training.

## 7. Data flow

**App launch** → `PlanKit` loads plan → `ReadinessMonitor` reads sleep/RHR/HRV → Today view
shows the session, plus any gate-driven downgrade ("4h sleep — today's intervals are now an
easy run").

**Pre-run** → if network: `AIProvider.brief()` → cache `SessionBrief` + cue bundle. If no
network: generic zone rules. Either way the run can start.

**During run** → `WorkoutEngine` drives segments off `HKWorkoutSession` → `AsyncStream<LiveMetrics>`
→ `CoachEngine.evaluate()` → haptic + text cue. Entirely offline.

**Post-run** → save to HealthKit → `CompletedWorkout` → if network: `AIProvider.analyze()` →
summary. If not: queue and retry on next launch.

**Sunday night** → `AIProvider.adapt()` → `PlanMutation` → `MutationValidator` → applied or
rejected with reason.

## 8. Error handling

| Failure | Behaviour |
|---|---|
| No network pre-run | Generic zone cue rules. Run proceeds normally. |
| No network post-run | Analysis queued, retried on next launch. |
| No API key configured | AI features disabled; app is a fully functional tracker. |
| HealthKit permission denied | Today view degrades to plan-only; readiness gates disabled behind a visible banner. |
| Workout session interrupted | `HKWorkoutSession` pause/resume; partial workout persisted so a crash never loses a run. |
| LLM returns undecodable JSON | Decode fails → proposal discarded → plan unchanged → surfaced as "coach couldn't decide". |
| LLM proposes illegal mutation | Validator rejects with reason; logged and shown; plan stands. |
| Provider outage | Configurable fallback to the other provider. |

Principle: **every AI failure degrades to a working app.** Nothing the LLM does can prevent a
run from being tracked.

## 9. Testing

Concentrated where the logic is, which is deliberately where the dependencies aren't.

- **CoachEngine** — synthetic `LiveMetrics` streams; assert cues fire at the right moments and
  don't repeat. Pure functions, no mocking needed.
- **MutationValidator** — property tests: no accepted mutation may violate any `immutable` rule,
  for any generated input. This is the highest-value test suite in the project.
- **PlanKit** — round-trip decode of the real `half-2026-09-27.json`; `session(on:)` correctness
  across timezone and DST boundaries.
- **WorkoutEngine** — segment state machine advances correctly for each session shape in the
  plan (easy, tempo, intervals, long run/walk, race).
- **AIProvider** — fake implementations returning canned *and hostile* responses (malformed
  JSON, illegal mutations, empty cue bundles).

Integration on a real watch is manual and continuous — the athlete runs with it four times a
week, which is the best test harness available.

## 10. Staging

| Stage | Ships | Content |
|---|---|---|
| 1 | wk 1 | Live tracking: `HKWorkoutSession`, HR/pace/distance/splits, auto-split haptics, saves to HealthKit. **No AI.** |
| 2 | wk 2 | `PlanKit` consumes the JSON. Today's session, week browser, mark done/skipped. |
| 3 | wk 3 | `CoachEngine` + generic zone rules. Live cues, haptics. Still no network. |
| 4 | wk 4 | `AIProvider` (OpenAI + Gemini), `brief()` with cue bundles, `analyze()` post-run. |
| 5 | wk 5–6 | `adapt()` + `MutationValidator`. Weekly plan rewriting. |
| — | 2026-09-13 | **Feature freeze.** Bug fixes only through race day. |

Stage 1 carries no AI on purpose: it is the highest-risk component (session lifecycle,
background execution, HealthKit permissions), it is needed on every single run, and it starts
banking training data from week one — so that by the time stage 4 lands, the AI has four weeks
of real running to reason about.

## 11. Out of scope

iPhone companion app · backend server · multi-user or accounts · App Store distribution ·
watch complications · social features · route mapping · music control · nutrition tracking ·
plan authoring in-app (plans are generated offline and loaded as JSON).

## 12. Open questions

1. **HealthKit history depth on watchOS** — how far back can the watch's local store be queried
   for sleep, RHR, HRV, and VO2max? Resolved by a day-1 spike in stage 1. If the answer is
   "not far enough", `ReadinessMonitor` computes rolling baselines from data it accumulates
   itself rather than from history, which is slower to become useful but requires no iPhone.
2. **Which provider first** — OpenAI or Gemini. Both are implemented behind `AIProviding`;
   only the default and the key in `Secrets.xcconfig` differ.
