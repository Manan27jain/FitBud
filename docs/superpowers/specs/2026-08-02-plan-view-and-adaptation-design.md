# Plan Browsing and Adaptation — Design

**Date:** 2026-08-02
**Status:** Approved for planning
**Follows:** `2026-07-31-fitbud-ai-coach-design.md` §6.2, which specified a mutation
validator that was never built.

Two features the athlete asked for, in one design because the second is invisible
without the first:

1. **See the whole plan.** Today the home screen shows only today's session. The
   nine-week block it comes from cannot be viewed at all.
2. **Let completed runs reshape what remains.** When reality diverges from the plan,
   the rest of the block should adjust — with the athlete approving every change.

---

## 1. What exists, and what is missing

`half-2026-09-27.json` ships in the bundle: nine weeks (a two-day calibration bridge
indexed 0, then training weeks 1–8), each with seven days. `PlanStore.loadBundled()`
decodes it into `TrainingPlan`. `blockProgress(plan:runs:asOf:)` derives the current
week's volume, session count and easy-share from HealthKit runs.

Four gaps block this work:

- **No way to see the plan.** The home screen's "All sessions" link is misleadingly
  named: `SessionListView` offers three hardcoded ad-hoc workouts (`openEasyRun`,
  `longRun4to1`, `longRun5to1`), not the plan.
- **The `rules` block is never decoded.** `TrainingPlan` reads `planId`, `goal` and
  `weeks` only. The `rules` object — progression caps, immutable weeks, zone
  discipline — is present in the JSON and invisible to Swift.
- **`AIProviding` has no `adapt()`.** It has `brief()`, `liveCue()` and `analyze()`.
- **No persistence of any kind.** The app has never written mutable state. This
  design introduces the first, and `PlanStore` already anticipates it:
  *"Stage 4 will rewrite the plan in place after each week; this loader is where that
  persisted copy will take precedence over the bundled one."*

## 2. Decisions taken

| Question | Decision |
|---|---|
| How much authority does adaptation have? | **Proposes; the athlete approves.** Nothing changes without a tap. Accepted changes are revertible. |
| What may a change express? | **Reduced targets and downgraded intensity.** Never an increase in either. |
| How far can one proposal reach? | **The whole remaining block**, under a per-week ceiling. |
| How is the plan browsed? | **Week list → days → day detail.** |
| What is deterministic vs. AI? | **The engine sets ceilings; the AI allocates under them.** |

## 3. The bundled plan is never rewritten

`half-2026-09-27.json` was generated from the athlete's real Apple Health export and
validated against its own progression caps. Rewriting it in place destroys the thing
that makes it trustworthy, and makes "what did this used to be?" unanswerable.

Instead, accepted proposals accumulate in a small **overlay**:

```
effectivePlan = bundledPlan + overlay.accepted (applied in order)
```

The original is always present, so displaying `was 19 km` is free and reverting is a
deletion rather than a restore.

```swift
/// One day's change. `nil` means "leave this field alone".
struct PlanChange: Codable, Equatable, Sendable {
    let date: String          // yyyy-MM-dd
    let targetKm: Double?
    let targetMin: Double?
    let type: String?         // downgrade only, e.g. "easy"
    let zone: String?         // downgrade only, e.g. "Z2"
}

struct PlanProposal: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let planId: String        // refuses to apply to a different plan
    let createdOn: String     // yyyy-MM-dd
    let affectedWeeks: [Int]
    let trigger: DivergenceReason
    let changes: [PlanChange]
    /// Why, in the athlete's language. LLM-written, or templated offline.
    /// Capped at 240 characters at decode time, as `CueRule.message` caps words.
    let reason: String
}

struct PlanOverlay: Codable, Equatable, Sendable {
    let planId: String
    var accepted: [PlanProposal]
}
```

Storing whole accepted *proposals* rather than bare changes keeps the reason attached
to the change that carries it, and makes revert-by-`id` a one-liner.

**Persistence:** the encoded overlay in `UserDefaults`, behind a `PlanOverlayStoring`
protocol so tests use an in-memory fake — the same seam pattern as `WorkoutRecording`,
`AIProviding` and `WorkoutHistoryReading`. A few hundred bytes does not justify the
error surface of file I/O.

**Acceptance is all-or-nothing.** The weeks of a proposal are a chain: accepting week 2
but not week 3 breaks the projection week 3 was computed from. One proposal, one
decision, one revert.

## 4. Half the rules block is prose, and the validator cannot read prose

`progressionCaps` is machine-readable and the validator consumes it directly:

```json
"progressionCaps": { "weeklyKmIncreaseMax": 0.2, "longRunIncreaseMaxKm": 2.0 }
```

`immutable` is not:

```json
"immutable": [
  "Week 4 cutback cannot be removed or upgraded",
  "Weeks 7-8 cannot be increased in volume or intensity",
  "Long run never exceeds 16km before race day",
  "Quality sessions never exceed 2 per week"
]
```

These four become named cases **in code**, with the JSON string displayed alongside as
the human-readable citation when a proposal is rejected. The JSON remains the
documentation; the code is the enforcement. Restructuring the JSON to make them
machine-readable would mean regenerating a plan that is otherwise correct, for no gain
this feature needs.

**Week 4 needs interpretation.** Read literally, "cannot be removed or upgraded" would
freeze week 4 at 17 km while the weeks around it shrink — and a 17 km week between a
17.4 km week and a 20.9 km week is not a cutback. The rule's intent is that week 4
remains a genuine absorption week, so it is encoded as: **week 4 may fall, never rise,
and must stay at or below 77% of week 3's effective target** — the ratio the bundled
plan itself uses (17 / 22).

## 5. Ceilings by forward projection

Week 2's ceiling derives from week 1's *actual* completed volume. Week 3's derives from
week 2's actual — which has not happened yet. So future ceilings are computed by
chaining forward on the assumption that each proposed week is completed in full.

The projection self-corrects: every completed week re-runs the detector and re-projects
from the new reality.

```
week 1 planned 16 km · actual 12.1 km · long run 8 km
                    │  chain +20% volume, +2 km long-run steps
                    ▼
W2 14.5   W3 17.4   W4 13.4 (cutback held at 77%)   W5 20.9
W6 25.1   W7 21.5 (taper)   W8 race — 21.1 km untouchable
```

Every value is also floored by rule 8 below: no week may exceed its original bundled
target. The chain produces a *budget*, never a mandate.

The projection's most useful output is the one the plan alone could never give: the
**longest run reachable before race day**. Chaining +2 km steps from the last completed
long run answers whether a safe 21.1 km is still on the table. Sometimes it confirms the
block absorbs the shortfall; sometimes it says the longest run will be 14 km rather than
16, and the athlete deserves to know that in August rather than discover it in
September. That answer is an input to the AI's reason text, not a separate feature.

## 6. The engine sets the ceiling; the AI spends under it

Arithmetic can determine *that* a rule broke and *what the ceiling is*. It cannot
determine how to spend the budget: cutting 19 km to 14.5 km proportionally shaves the
long run, but the long run is the adaptation that matters for a half, and 8 km was this
athlete's longest run ever. Protecting it and taking the reduction out of midweek is
judgment.

Nor can arithmetic act on evidence that breaches no single threshold — 4.7 h median
sleep, resting HR +5, easy-share 45%, and the fade cue firing twice in one session.
Encoding every such combination as thresholds is the rule-explosion the cue-bundle
design already rejected once.

```
ENGINE  (pure · Foundation-only · offline · from the rules block)
    actual volume, actual long run, easy share, missed sessions
    → per-week ceilings, long-run ceilings, locked weeks
                    │  budget + evidence
                    ▼
AI  adapt(context) -> PlanProposal?
    decides WHETHER to propose, WHICH days absorb the change,
    whether to also downgrade intensity, and WHY — all strictly
    at or below the ceilings it was given
                    ▼
VALIDATOR  re-checks all 8 rules against the AI's own output
                    ▼
PROPOSAL → athlete accepts or keeps the original
```

**The AI can never raise a ceiling — only decide how to spend under one.** A bad model
response degrades to a rejected proposal, never to a dangerous week. Returning `nil` is
a valid and expected answer: most weeks warrant no change.

```swift
protocol AIProviding: Sendable {
    // ...existing brief/liveCue/analyze...
    func adapt(context: AdaptationContext) async throws -> PlanProposal?
}

struct AdaptationContext: Sendable {
    let planId: String
    let asOf: String
    let divergence: PlanDivergence      // which rule broke, and by how much
    let ceilings: [WeekCeiling]         // the budget — one per remaining week
    let remainingWeeks: [PlanWeekSummary]
    let recentRuns: [RunSummary]
    let easyShare: Double?
    let sleepHours: Double?             // nil-safe; from HealthHistoryProbe
    let restingHRDelta: Double?
    let raceDate: String
    let raceDistanceKm: Double
}

struct WeekCeiling: Codable, Equatable, Sendable {
    let weekIndex: Int
    let maxKm: Double
    let maxLongRunKm: Double
    let locked: Bool
}
```

`adapt()` uses `response_format: json_schema` with `"strict": true`, matching how
`brief()` already decodes structured output from `gpt-5-mini`.

## 7. The validator — 8 rules, over the whole chain

| # | Rule | Source |
|---|---|---|
| 1 | Each week ≤ +20% over the prior non-cutback week (actual, or projected if future) | JSON `progressionCaps` |
| 2 | Long run rises ≤ +2 km per step | JSON `progressionCaps` |
| 3 | Week 4 may fall, never rise, and stays ≤ 77% of week 3 | code |
| 4 | Weeks 7–8 may fall, never rise, in volume or intensity | code |
| 5 | Long run never exceeds 16 km before race day | code |
| 6 | No more than 2 quality sessions (`tempo`, `intervals`) per week | code |
| 7 | Only days after today — never a day already run | code |
| 8 | Never above the original bundled target for any day or week | code |

Rule 8 is what makes whole-block scope safe. The bundled plan is a validated envelope;
adaptation reshapes *downward inside it* and can never add load because the athlete had
one good week. Rule 1 generalises from a pairwise comparison to a fold over the week
sequence.

A proposal violating any rule is rejected, named by the rule it broke, and the plan
stands unchanged.

## 8. Two clocks, deliberately

Mid-week the athlete is *always* behind plan, so evaluating volume after every run would
raise a false alarm every Tuesday.

| Trigger | Checks that run |
|---|---|
| A run completes | Long-run step, easy-share, missed sessions |
| A week has ended (`week.end < today`) | The above, plus volume shortfall and forward projection |

Both live in one pure function, `planDivergence(plan:runs:asOf:)`, shaped like the
existing `blockProgress(plan:runs:asOf:)`. A proposal surfaces only when a rule is
genuinely breached — not whenever reality differs from plan. **Silence is the common
case and the correct one.**

## 9. Interface

```
┌──── Proposal ────┐        ┌──── Plan ────┐        ┌── Week 2 ──┐
 REBUILD THE BASE           WEEK 1 · 16 km          Mon  Rest
                            ▓▓▓▓▓▓░░ 12.1/16        Tue  Easy 3.5 km
 You ran 12.1 of 16 km.                             Wed  Strength
 Rest of the block          WEEK 2 · 14.5 km ●      Thu  Easy 3 km
 re-shaped. Longest run     adjusted · was 19       Fri  Rest
 before race: 14 km.                                Sat  Strength
                            WEEK 3 · 17.4 km ●      Sun  Long 8 km
 W2   19  → 14.5            adjusted · was 22
 W3   22  → 17.4                                   └────────────┘
 W4   17  → 13.4  🔒        WEEK 4 · 13.4 km 🔒      tap day → detail
 W5   26  → 20.9            CUTBACK — immutable
 W6   28  → 25.1
 W7   24  → 21.5            WEEK 5 · 20.9 km ●
 W8  21.1    race           ...

 [ Accept ]   [ Keep ]     └──────────────┘
└──────────────────┘
```

### Files

| File | Responsibility |
|---|---|
| `Models/PlanChange.swift` | `PlanChange`, `PlanProposal`, `PlanOverlay`, `DivergenceReason` |
| `Models/PlanRules.swift` | Decodes the `rules` block `TrainingPlan` currently ignores |
| `Models/PlanOverlayStore.swift` | `PlanOverlayStoring` protocol + `UserDefaults` implementation |
| `Engine/PlanProjection.swift` | Forward-chains ceilings from actual completed volume |
| `Engine/PlanDivergence.swift` | `planDivergence(plan:runs:asOf:)` — detects breaches |
| `Engine/MutationValidator.swift` | The 8 rules, over a whole chain |
| `UI/PlanWeekListView.swift` | The nine-week browser |
| `UI/PlanWeekDetailView.swift` | One week's seven days |
| `UI/PlanDayDetailView.swift` | Notes, segments, and Start for running sessions |
| `UI/ProposalView.swift` | Accept / Keep original |

**Modified:** `PlanStore` gains `effectivePlan(overlay:)`; `TrainingPlan` decodes
`rules`; `Models/CoachContext.swift` gains `AdaptationContext`, `WeekCeiling`,
`PlanWeekSummary` and `RunSummary` alongside the existing `CoachContext` and
`LiveCoachContext`; `AIProviding` and `OpenAIProvider` gain `adapt()`;
`DemoAIProvider` gains a scripted proposal; `HomeView` gains a pending-proposal card
and a **Training plan** link, and its misleading **All sessions** link is renamed
**Quick start**.

**Constraints preserved:** `Models/` and `Engine/` import Foundation only, never
SwiftUI. `Health/HealthKitWorkoutRecorder.swift` and `Health/WorkoutRecording.swift`
are not touched. `project.pbxproj` is not edited — new files are picked up by the
synchronized folder group.

## 10. Error handling

| Failure | Behaviour |
|---|---|
| No network when a breach is detected | Deterministic proportional trim under the same ceilings, plus a templated reason. The proposal still appears. |
| AI returns a mutation that breaks a rule | Validator rejects it by name. No proposal shown. Plan stands. |
| AI returns `nil` | No proposal. This is a normal outcome, not an error. |
| AI unreachable *and* fallback yields nothing | Nothing shown. Plan unchanged. App fully functional. |
| Overlay fails to decode (schema drift) | Discarded; the bundled plan is used. A run is never blocked by a bad overlay. |
| Overlay's `planId` ≠ bundled `planId` | Discarded. A future regenerated plan invalidates old adaptations cleanly. |
| HealthKit read fails | No divergence can be computed; no proposal. The browser still works. |

Adaptation is never on a workout's critical path. Every failure above degrades to "the
plan you already had".

## 11. Testing

Every decision-making component is pure, so the suites are table-driven Swift Testing
(`@Test`/`#expect`) with no mocks:

- **Projection** — chains from a known actual; cutback ratio held; race distance never
  scaled; terminal long run computed correctly at several shortfall depths.
- **Validator** — each of the 8 rules, both rejecting an illegal proposal and accepting
  a legal one; the multi-week fold; rule 8 against every day.
- **Divergence** — mid-week silence (the false-alarm case), end-of-week firing,
  no-breach silence, missing HealthKit data.
- **Overlay** — round-trip through the in-memory fake; revert by `id`; `planId`
  mismatch discarded; undecodable payload discarded.
- **Provider** — `FakeAIProvider` returning a deliberately illegal mutation proves the
  validator catches it; returning `nil` proves silence is handled.

Estimated **+45–60 tests** on the current 193.

## 12. Sequencing — two implementation plans

**Plan A — the browser.** Decode `rules`, add `effectivePlan()` (overlay support with
an always-empty overlay), build the three browse views, rename **All sessions** to
**Quick start**. Ships and is independently useful: the athlete can see the whole block.

**Plan B — adaptation.** Projection, divergence, validator, overlay persistence,
`adapt()`, the proposal UI, and the adjusted badges the browser already has room for.

Built as one plan, nothing is verifiable until everything works. Built as two, the first
delivers value on its own and the second has a surface to render into.

## 13. Out of scope

- **Rescheduling.** Moving a session to a different day is an athlete action, not an
  adaptation; it needs its own design.
- **Regenerating the block.** The bundled plan stays the envelope. A genuinely new plan
  is a new JSON with a new `planId`, which cleanly invalidates the overlay.
- **Readiness gates.** The `sleepGate` and `recoveryGate` rules downgrade *today's*
  session; that is a separate feature from reshaping future weeks. Sleep and resting-HR
  values are passed into `AdaptationContext` as evidence here, but no gate is enforced.
- **Race-day mode**, deferred from the original spec, remains deferred.

## 14. Known limitations

- The forward projection assumes each proposed week is completed in full. It is a
  projection, not a prediction; it is re-derived after every completed week.
- `HealthHistoryProbe` currently returns zero samples on the simulator, so sleep and
  resting-HR evidence will be `nil` there. Every field is nil-safe and the feature
  degrades to volume and pace evidence alone.
- Rule 6 counts quality sessions by `type`; a downgrade that turns `intervals` into
  `easy` therefore also reduces that count, which is intended.
- The four `immutable` rules are enforced in code while their text lives in JSON. If
  the JSON text is ever edited without the code, they drift. The plan JSON is
  regenerated rarely enough that this is accepted rather than solved.
