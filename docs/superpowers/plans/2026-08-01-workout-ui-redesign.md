# Workout UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder workout UI with a crown-paged, number-led interface whose effort ring makes heart-rate zone drift unmissable at a glance.

**Architecture:** All new logic is pure and lives below the views — zone classification, ring geometry, time-in-zone accumulation, phase fractions — each unit tested without rendering. The views are thin readers of `WorkoutState`. `LiveWorkoutView` becomes a `TabView` with `.tabViewStyle(.verticalPage)` hosting five pages. `HealthKitWorkoutRecorder` and `WorkoutRecording` are **not touched**.

**Tech Stack:** Swift 5, SwiftUI (`Canvas`, `TabView` `.verticalPage`, `.containerBackground`), Swift Testing, watchOS 11.2.

## Global Constraints

- Deployment target **watchOS 11.2**, Swift **5.0** language mode.
- Test framework is **Swift Testing** (`import Testing`, `@Test`, `#expect`). Never XCTest.
- Test module: `@testable import FitBud_Watch_App`.
- Build/test command (both verified working):
  `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test`
  Always pipe through `grep -E "✔|✘|error:|\*\* TEST"` — raw output is enormous.
- Simulator: **Apple Watch Series 10 (46mm)**, UUID `ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5`.
- Xcode 16 **synchronized folder groups** (`objectVersion = 77`): new `.swift` files compile automatically. **Never edit `project.pbxproj`.** `xcodebuild` cosmetically re-sorts it on most runs — revert with `git checkout -- FitBud.xcodeproj/project.pbxproj`, never commit it.
- **Never modify** `Health/HealthKitWorkoutRecorder.swift` or `Health/WorkoutRecording.swift`. The final Stage 1 review found two Critical defects there; it is now hardened and verified.
- `WorkoutSessionModel` is owned by `FitBudApp`, not by `RootView`. Ownership must stay at App scope or a scene rebuild orphans a live `HKWorkoutSession`.
- **`Models/` and `Engine/` must not import SwiftUI.** `WorkoutState` is held by `WorkoutEngine`, which the spec requires to stay Foundation-only. Zone *colours* therefore live in `UI/Theme.swift`, never on `HRZone`.
- Zone table (Karvonen, HRmax 207 observed, RHR 60), copied verbatim from spec §5:

  | Zone | Name | BPM | Hex |
  |---|---|---|---|
  | Z1 | Recovery | 133–148 | `#32ADE6` |
  | Z2 | Easy | 148–163 | `#30D158` |
  | Z3 | Steady | 163–177 | `#C6F432` |
  | Z4 | Threshold | 177–192 | `#FF9F0A` |
  | Z5 | VO2max | 192–207 | `#FF375F` |

  Inactive zone segments: same hue at **22% opacity**. Elapsed time: system yellow `#FFD60A`.
- Ring geometry, copied verbatim from spec §4: sweep **240°, from 150° to 30°** (SwiftUI convention, 0° = 3 o'clock, clockwise), gap centred on the bottom. `angle = 150 + ((bpm − 133) / 74) × 240`, clamped to `[133, 207]`.
- On the **ring**, the active segment brightens but its **width never changes**. On the **Zones page** the active segment *does* widen to carry its caption.
- Suite is **56 tests** at the start of this plan. Each task states its expected total.
- No cards, no rounded-rectangle containers, no dividers. Black background, left-aligned type.

## File Structure

```
FitBud Watch App/
  Models/
    HRZone.swift              NEW  Zone model, table, classification. Foundation only.
    ZoneBreakdown.swift       NEW  Pure time-in-zone → display fractions.
    WorkoutState.swift        MOD  + currentZone, timeInZone, averageHeartRate, phaseRemainingFraction
  Engine/
    RunWalkCycler.swift       MOD  + remainingFraction(at:)
    WorkoutEngine.swift       MOD  accumulate zone time, average HR, phase fraction
  UI/
    Theme.swift               NEW  Zone colours, accent colours, opacity constants.
    EffortRingGeometry.swift  NEW  Pure angle maths. No SwiftUI.
    EffortRingView.swift      NEW  Canvas-drawn ring. Presentation only.
    EffortPage.swift          NEW  Page 1 — ring + centre readout.
    ZonesPage.swift           NEW  Page 2 — five-segment bar, time in zone, avg HR.
    MetricsPage.swift         NEW  Page 3 — elapsed, distance, pace, energy.
    SplitsPage.swift          NEW  Page 4 — per-km rows with pace bars.
    ControlsPage.swift        NEW  Page 0 — pause/resume, end.
    ZoneBreakdownBar.swift    NEW  Stacked bar, shared by ZonesPage and SummaryView.
    LiveWorkoutView.swift     MOD  Becomes the verticalPage TabView host.
    StartView.swift           MOD  Carousel rows + DEBUG demo entry.
    SummaryView.swift         MOD  Hero numbers + zone breakdown.
  Support/
    DemoWorkoutRecorder.swift NEW  DEBUG-only scripted HR sweep for visual verification.

FitBud Watch AppTests/
  HRZoneTests.swift               NEW
  EffortRingGeometryTests.swift   NEW
  ZoneBreakdownTests.swift        NEW
  RunWalkCyclerTests.swift        MOD  + remainingFraction cases
  WorkoutEngineTests.swift        MOD  + zone accumulation cases
```

**Task 6 (the demo recorder) deliberately comes before every view task.** The simulator supplies synthetic distance but no heart rate, so without it the ring and zone views cannot be seen at all and "verification" would collapse into "it compiled".

---

### Task 1: HRZone model, table and classification

**Files:**
- Create: `FitBud Watch App/Models/HRZone.swift`
- Test: `FitBud Watch AppTests/HRZoneTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `HRZone` (`Identifiable, Equatable, Sendable`) with `id: String`, `name: String`, `lowerBPM: Int`, `upperBPM: Int`, `func contains(_:) -> Bool`; statics `HRZone.table: [HRZone]`, `HRZone.lowerBound: Int`, `HRZone.upperBound: Int`, `HRZone.zone(for: Double) -> HRZone?`

**Foundation only — no `import SwiftUI`.** Colours arrive in Task 5.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/HRZoneTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct HRZoneTests {
    @Test func tableCoversFiveZonesFrom133To207() {
        #expect(HRZone.table.count == 5)
        #expect(HRZone.table.map(\.id) == ["Z1", "Z2", "Z3", "Z4", "Z5"])
        #expect(HRZone.lowerBound == 133)
        #expect(HRZone.upperBound == 207)
    }

    @Test func zonesAreContiguousWithNoGapsOrOverlaps() {
        for (lower, upper) in zip(HRZone.table, HRZone.table.dropFirst()) {
            #expect(lower.upperBPM == upper.lowerBPM)
        }
    }

    @Test func theAthletesEasyZoneIs148To163() {
        let easy = HRZone.table[1]
        #expect(easy.id == "Z2")
        #expect(easy.name == "Easy")
        #expect(easy.lowerBPM == 148)
        #expect(easy.upperBPM == 163)
    }

    @Test func boundaryHeartRateBelongsToTheZoneItOpens() {
        // 148 is the first beat of Z2, not the last of Z1.
        #expect(HRZone.zone(for: 148)?.id == "Z2")
        #expect(HRZone.zone(for: 147)?.id == "Z1")
        #expect(HRZone.zone(for: 163)?.id == "Z3")
    }

    @Test func heartRatesInsideEachZoneClassifyCorrectly() {
        #expect(HRZone.zone(for: 140)?.id == "Z1")
        #expect(HRZone.zone(for: 155)?.id == "Z2")
        #expect(HRZone.zone(for: 170)?.id == "Z3")
        #expect(HRZone.zone(for: 185)?.id == "Z4")
        #expect(HRZone.zone(for: 200)?.id == "Z5")
    }

    @Test func heartRateAtOrAboveMaxSaturatesToTheTopZone() {
        // 207 is the observed max, and anything at or beyond it is still Z5
        // rather than falling off the end of the table.
        #expect(HRZone.zone(for: 207)?.id == "Z5")
        #expect(HRZone.zone(for: 240)?.id == "Z5")
    }

    @Test func heartRateBelowTheFirstZoneHasNoZone() {
        // Resting and walking heart rates are genuinely outside the training
        // zones; reporting Z1 for a resting 62 bpm would be a lie.
        #expect(HRZone.zone(for: 132) == nil)
        #expect(HRZone.zone(for: 60) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'HRZone' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Models/HRZone.swift`:
```swift
import Foundation

/// A heart-rate training zone.
///
/// Deliberately free of any `SwiftUI` dependency: `WorkoutState` holds a zone
/// and `WorkoutEngine` holds a `WorkoutState`, and the engine is required to
/// stay Foundation-only so it remains testable without a UI. Zone colours live
/// in `UI/Theme.swift`.
struct HRZone: Identifiable, Equatable, Sendable {
    /// `"Z1"` … `"Z5"`. Matches the zone ids used in the plan JSON, so Stage 2
    /// can load this table from the plan instead of hardcoding it.
    let id: String
    let name: String
    let lowerBPM: Int
    let upperBPM: Int

    /// Half-open: the lower bound belongs to this zone, the upper bound belongs
    /// to the next one. Without that rule 148 would be in both Z1 and Z2.
    func contains(_ bpm: Double) -> Bool {
        bpm >= Double(lowerBPM) && bpm < Double(upperBPM)
    }
}

extension HRZone {
    /// Karvonen zones for this athlete: max heart rate 207 (observed in the
    /// Health export, not age-estimated) and resting 60.
    static let table: [HRZone] = [
        HRZone(id: "Z1", name: "Recovery",  lowerBPM: 133, upperBPM: 148),
        HRZone(id: "Z2", name: "Easy",      lowerBPM: 148, upperBPM: 163),
        HRZone(id: "Z3", name: "Steady",    lowerBPM: 163, upperBPM: 177),
        HRZone(id: "Z4", name: "Threshold", lowerBPM: 177, upperBPM: 192),
        HRZone(id: "Z5", name: "VO2max",    lowerBPM: 192, upperBPM: 207)
    ]

    static var lowerBound: Int { table[0].lowerBPM }
    static var upperBound: Int { table[table.count - 1].upperBPM }

    /// The zone a heart rate falls in, or `nil` below the first zone.
    ///
    /// At or above the top of Z5 the answer saturates to Z5 rather than going
    /// nil — a heart rate of 210 is emphatically still in the top zone.
    static func zone(for bpm: Double) -> HRZone? {
        if bpm >= Double(upperBound) { return table.last }
        return table.first { $0.contains(bpm) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **63 tests** (56 + 7).

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/HRZone.swift" "FitBud Watch AppTests/HRZoneTests.swift"
git commit -m "feat: add heart rate zone model and classification"
```

---

### Task 2: Effort ring geometry

**Files:**
- Create: `FitBud Watch App/UI/EffortRingGeometry.swift`
- Test: `FitBud Watch AppTests/EffortRingGeometryTests.swift`

**Interfaces:**
- Consumes: `HRZone.lowerBound`, `HRZone.upperBound`, `HRZone` from Task 1
- Produces: `EffortRingGeometry` (an `enum` namespace) with `static let startAngle: Double`, `static let sweep: Double`, `static var endAngle: Double`, `static func angle(forHeartRate: Double) -> Double`, `static func arc(for: HRZone) -> (start: Double, end: Double)`

Despite living in `UI/`, this file imports **Foundation only** — it is pure arithmetic and is tested without rendering anything. That is the whole point of separating it from `EffortRingView`.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/EffortRingGeometryTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct EffortRingGeometryTests {
    @Test func arcSpans240DegreesLeavingAGapAtTheBottom() {
        #expect(EffortRingGeometry.startAngle == 150)
        #expect(EffortRingGeometry.sweep == 240)
        #expect(EffortRingGeometry.endAngle == 390)
    }

    @Test func lowestTrainingHeartRateSitsAtTheStartOfTheArc() {
        #expect(EffortRingGeometry.angle(forHeartRate: 133) == 150)
    }

    @Test func maximumHeartRateSitsAtTheEndOfTheArc() {
        #expect(EffortRingGeometry.angle(forHeartRate: 207) == 390)
    }

    @Test func midRangeHeartRateSitsHalfwayAround() {
        // 170 is 37 of the 74 bpm span, so exactly half of 240 degrees.
        #expect(abs(EffortRingGeometry.angle(forHeartRate: 170) - 270) < 0.001)
    }

    @Test func heartRatesOutsideTheRangeClampInsteadOfWrapping() {
        // Wrapping would put the needle inside the bottom gap, where it would
        // read as a completely different effort.
        #expect(EffortRingGeometry.angle(forHeartRate: 60) == 150)
        #expect(EffortRingGeometry.angle(forHeartRate: 250) == 390)
    }

    @Test func eachZonesArcMatchesItsShareOfTheHeartRateRange() {
        let easy = HRZone.table[1] // Z2, 148-163
        let arc = EffortRingGeometry.arc(for: easy)
        #expect(abs(arc.start - (150 + (15.0 / 74.0) * 240)) < 0.001)
        #expect(abs(arc.end - (150 + (30.0 / 74.0) * 240)) < 0.001)
    }

    @Test func zoneArcsAreContiguousAndFillTheWholeSweep() {
        let arcs = HRZone.table.map(EffortRingGeometry.arc(for:))
        #expect(abs(arcs[0].start - 150) < 0.001)
        #expect(abs(arcs[arcs.count - 1].end - 390) < 0.001)
        for (lower, upper) in zip(arcs, arcs.dropFirst()) {
            #expect(abs(lower.end - upper.start) < 0.001)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'EffortRingGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/UI/EffortRingGeometry.swift`:
```swift
import Foundation

/// Pure geometry for the effort ring.
///
/// Angles are degrees in SwiftUI's convention: 0° is 3 o'clock and angles
/// increase clockwise. Kept separate from `EffortRingView` so the arithmetic
/// can be tested without rendering — which is where the bugs would be.
enum EffortRingGeometry {
    /// The arc sweeps 240°, leaving a 120° gap centred on the bottom of the
    /// screen for the phase countdown. A tachometer, not a closed ring.
    static let startAngle: Double = 150
    static let sweep: Double = 240
    static var endAngle: Double { startAngle + sweep }

    /// Where a heart rate sits on the zone scale.
    ///
    /// Clamps rather than wrapping: a heart rate below Z1 pins to the start and
    /// one above Z5 pins to the end, so the needle can never stray into the
    /// bottom gap where it would imply an effort the athlete isn't at.
    static func angle(forHeartRate bpm: Double) -> Double {
        let lo = Double(HRZone.lowerBound)
        let hi = Double(HRZone.upperBound)
        let clamped = min(max(bpm, lo), hi)
        return startAngle + ((clamped - lo) / (hi - lo)) * sweep
    }

    /// The arc a zone occupies, proportional to its width in beats per minute
    /// rather than an equal fifth — so the scale tells the truth about
    /// physiology instead of flattering the layout.
    static func arc(for zone: HRZone) -> (start: Double, end: Double) {
        (angle(forHeartRate: Double(zone.lowerBPM)),
         angle(forHeartRate: Double(zone.upperBPM)))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **70 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/UI/EffortRingGeometry.swift" "FitBud Watch AppTests/EffortRingGeometryTests.swift"
git commit -m "feat: add effort ring geometry"
```

---

### Task 3: Run/walk phase remaining fraction

**Files:**
- Modify: `FitBud Watch App/Engine/RunWalkCycler.swift`
- Test: `FitBud Watch AppTests/RunWalkCyclerTests.swift` (append a new struct)

**Interfaces:**
- Consumes: existing `RunWalkCycler(runSeconds:walkSeconds:)`, `phase(at:)`, `remainingInPhase(at:)`
- Produces: `func remainingFraction(at: TimeInterval) -> Double`

The cycler must stay **stateless** — this is a derived value, not stored progress.

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/RunWalkCyclerTests.swift`:
```swift
struct RunWalkRemainingFractionTests {
    let fourToOne = RunWalkCycler(runSeconds: 240, walkSeconds: 60)

    @Test func startsFullAtTheBeginningOfARunInterval() {
        #expect(fourToOne.remainingFraction(at: 0) == 1.0)
    }

    @Test func drainsProportionallyThroughTheRunInterval() {
        #expect(abs(fourToOne.remainingFraction(at: 120) - 0.5) < 0.001)
        #expect(abs(fourToOne.remainingFraction(at: 180) - 0.25) < 0.001)
    }

    @Test func refillsWhenTheWalkBreakBegins() {
        // The fraction is of the *current* phase, so it resets to full at the
        // boundary rather than continuing to fall.
        #expect(fourToOne.remainingFraction(at: 240) == 1.0)
    }

    @Test func drainsProportionallyThroughTheWalkInterval() {
        #expect(abs(fourToOne.remainingFraction(at: 270) - 0.5) < 0.001)
    }

    @Test func staysWithinZeroAndOneAcrossAWholeCycle() {
        for second in stride(from: 0.0, through: 600.0, by: 0.5) {
            let fraction = fourToOne.remainingFraction(at: second)
            #expect(fraction >= 0)
            #expect(fraction <= 1)
        }
    }

    @Test func isUnaffectedByAJumpInElapsedTime() {
        // Statelessness check: a delayed or dropped sample must not desynchronise
        // the fraction, because it is recomputed from the clock every time.
        #expect(fourToOne.remainingFraction(at: 1_200) == 1.0)
        #expect(abs(fourToOne.remainingFraction(at: 1_320) - 0.5) < 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `value of type 'RunWalkCycler' has no member 'remainingFraction'`.

- [ ] **Step 3: Write the implementation**

Add to `FitBud Watch App/Engine/RunWalkCycler.swift`, inside the struct after `remainingInPhase(at:)`:
```swift
    /// Fraction of the current phase still to run: 1.0 the instant it begins,
    /// falling to 0 as it ends. The effort ring drains along this value, which
    /// is why it is of the *current* phase rather than of the whole cycle — the
    /// ring should refill when the walk break starts, not keep emptying.
    func remainingFraction(at elapsed: TimeInterval) -> Double {
        let total = phase(at: elapsed) == .run ? runSeconds : walkSeconds
        guard total > 0 else { return 0 }
        return remainingInPhase(at: elapsed) / total
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **76 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Engine/RunWalkCycler.swift" "FitBud Watch AppTests/RunWalkCyclerTests.swift"
git commit -m "feat: add run/walk phase remaining fraction"
```

---

### Task 4: Engine accumulates zone time, average HR and phase fraction

**Files:**
- Modify: `FitBud Watch App/Models/WorkoutState.swift`
- Modify: `FitBud Watch App/Engine/WorkoutEngine.swift`
- Test: `FitBud Watch AppTests/WorkoutEngineTests.swift` (append a new struct)

**Interfaces:**
- Consumes: `HRZone.zone(for:)` (Task 1), `RunWalkCycler.remainingFraction(at:)` (Task 3)
- Produces: `WorkoutState.currentZone: HRZone?`, `WorkoutState.timeInZone: [String: TimeInterval]`, `WorkoutState.averageHeartRate: Double?`, `WorkoutState.phaseRemainingFraction: Double?`

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/WorkoutEngineTests.swift`:
```swift
struct WorkoutEngineZoneTests {
    private func easyRunEngine() -> WorkoutEngine {
        WorkoutEngine(
            timeline: SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy")]),
            runWalk: RunWalkCycler(runSeconds: 240, walkSeconds: 60)
        )
    }

    @Test func classifiesTheCurrentZoneFromHeartRate() {
        var engine = easyRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 10, heartRate: 155))
        #expect(engine.state.currentZone?.id == "Z2")
    }

    @Test func currentZoneIsNilWithoutAHeartRateSample() {
        var engine = easyRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 10))
        #expect(engine.state.currentZone == nil)
    }

    @Test func accumulatesTimeInEachZoneAcrossTheInterval() {
        var engine = easyRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 0, heartRate: 155))    // Z2
        _ = engine.ingest(LiveMetrics(elapsed: 60, heartRate: 155))   // +60s Z2
        _ = engine.ingest(LiveMetrics(elapsed: 90, heartRate: 185))   // +30s Z4
        #expect(engine.state.timeInZone["Z2"] == 60)
        #expect(engine.state.timeInZone["Z4"] == 30)
    }

    @Test func attributesNothingForSamplesWithoutAHeartRate() {
        var engine = easyRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 0, heartRate: 155))
        _ = engine.ingest(LiveMetrics(elapsed: 60))                   // no HR
        #expect(engine.state.timeInZone["Z2"] == nil)
        #expect(engine.state.timeInZone.isEmpty)
    }

    @Test func timeInZoneNeverExceedsElapsed() {
        var engine = easyRunEngine()
        for second in stride(from: 0, through: 300, by: 10) {
            _ = engine.ingest(LiveMetrics(elapsed: Double(second), heartRate: 155))
        }
        let total = engine.state.timeInZone.values.reduce(0, +)
        #expect(total <= engine.state.elapsed)
    }

    @Test func reportsRunningAverageHeartRateAndPhaseFraction() {
        var engine = easyRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 0, heartRate: 150))
        _ = engine.ingest(LiveMetrics(elapsed: 120, heartRate: 160))
        #expect(engine.state.averageHeartRate == 155)
        // Halfway through a 240s run interval.
        #expect(abs((engine.state.phaseRemainingFraction ?? 0) - 0.5) < 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `value of type 'WorkoutState' has no member 'currentZone'`.

- [ ] **Step 3: Extend WorkoutState**

Add these properties to `WorkoutState` in `FitBud Watch App/Models/WorkoutState.swift`, after `phaseRemaining`:
```swift
    /// The zone the latest heart-rate sample falls in, or `nil` when there is no
    /// sample or it is below the lowest training zone.
    var currentZone: HRZone?

    /// Seconds spent in each zone, keyed by `HRZone.id`. Only intervals with a
    /// heart-rate sample are attributed, so this can total less than `elapsed`.
    var timeInZone: [String: TimeInterval] = [:]

    /// Running mean of the heart-rate samples seen so far. This is for live
    /// display only — `CompletedWorkout.averageHeartRate` uses HealthKit's own
    /// time-weighted average, which is the authoritative figure.
    var averageHeartRate: Double?

    /// Fraction of the current run/walk phase still remaining, 1 → 0. `nil` for
    /// sessions with no run/walk configured.
    var phaseRemainingFraction: Double?
```

- [ ] **Step 4: Extend WorkoutEngine**

In `FitBud Watch App/Engine/WorkoutEngine.swift`, add these stored properties alongside `lastPhase`:
```swift
    private var lastElapsed: TimeInterval?
    private var heartRateSum: Double = 0
    private var heartRateCount: Int = 0
```

In `ingest`, immediately after the four `state.*` assignments at the top, insert:
```swift
        // Attribute the interval since the previous sample to the zone the
        // athlete is in now. A sample with no heart rate is attributed to
        // nothing at all rather than being guessed at — a fabricated zone would
        // corrupt the one number the training plan is judged on.
        if let bpm = metrics.heartRate {
            let zone = HRZone.zone(for: bpm)
            state.currentZone = zone
            if let zone, let last = lastElapsed, metrics.elapsed > last {
                state.timeInZone[zone.id, default: 0] += metrics.elapsed - last
            }
            heartRateSum += bpm
            heartRateCount += 1
            state.averageHeartRate = heartRateSum / Double(heartRateCount)
        } else {
            state.currentZone = nil
        }
        lastElapsed = metrics.elapsed
```

Inside the existing `if let runWalk {` block, after `state.phaseRemaining` is set:
```swift
            state.phaseRemainingFraction = runWalk.remainingFraction(at: metrics.elapsed)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **82 tests**.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/Models/WorkoutState.swift" "FitBud Watch App/Engine/WorkoutEngine.swift" "FitBud Watch AppTests/WorkoutEngineTests.swift"
git commit -m "feat: accumulate time in zone, average HR and phase fraction"
```

---

### Task 5: Zone breakdown fractions

**Files:**
- Create: `FitBud Watch App/Models/ZoneBreakdown.swift`
- Test: `FitBud Watch AppTests/ZoneBreakdownTests.swift`

**Interfaces:**
- Consumes: `HRZone.table` (Task 1)
- Produces: `struct ZoneShare: Equatable, Sendable { let zone: HRZone; let seconds: TimeInterval; let fraction: Double }` and `func zoneShares(timeInZone: [String: TimeInterval]) -> [ZoneShare]`

Pure, so the stacked bar's proportions are tested rather than eyeballed.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/ZoneBreakdownTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct ZoneBreakdownTests {
    @Test func noRecordedTimeYieldsNoShares() {
        #expect(zoneShares(timeInZone: [:]).isEmpty)
    }

    @Test func sharesAreProportionalAndSumToOne() {
        let shares = zoneShares(timeInZone: ["Z2": 3_600, "Z3": 1_200])
        #expect(shares.count == 2)
        #expect(abs(shares.map(\.fraction).reduce(0, +) - 1.0) < 0.0001)
        let easy = shares.first { $0.zone.id == "Z2" }
        #expect(abs((easy?.fraction ?? 0) - 0.75) < 0.0001)
    }

    @Test func sharesComeBackInZoneOrderNotDictionaryOrder() {
        let shares = zoneShares(timeInZone: ["Z5": 60, "Z1": 60, "Z3": 60])
        #expect(shares.map(\.zone.id) == ["Z1", "Z3", "Z5"])
    }

    @Test func zonesWithNoTimeAreOmitted() {
        // A run entirely in Z2 should render one solid bar, not five with four
        // of them zero-width.
        let shares = zoneShares(timeInZone: ["Z2": 1_800])
        #expect(shares.count == 1)
        #expect(shares[0].fraction == 1.0)
        #expect(shares[0].seconds == 1_800)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'zoneShares' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Models/ZoneBreakdown.swift`:
```swift
import Foundation

/// One zone's slice of a workout, ready for a stacked bar.
struct ZoneShare: Equatable, Sendable {
    let zone: HRZone
    let seconds: TimeInterval
    /// Share of the total *recorded* zone time, 0…1.
    let fraction: Double
}

/// Turns accumulated zone times into proportional shares in zone order.
///
/// Zones with no recorded time are omitted so a run spent entirely in Z2 draws
/// one solid bar rather than five, four of them zero-width. Fractions are of
/// recorded zone time, not of elapsed time — intervals with no heart-rate
/// sample belong to no zone and must not silently shrink the bar.
func zoneShares(timeInZone: [String: TimeInterval]) -> [ZoneShare] {
    let total = timeInZone.values.reduce(0, +)
    guard total > 0 else { return [] }
    return HRZone.table.compactMap { zone in
        guard let seconds = timeInZone[zone.id], seconds > 0 else { return nil }
        return ZoneShare(zone: zone, seconds: seconds, fraction: seconds / total)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **86 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/ZoneBreakdown.swift" "FitBud Watch AppTests/ZoneBreakdownTests.swift"
git commit -m "feat: add zone breakdown fractions"
```

---

### Task 6: Theme

**Files:**
- Create: `FitBud Watch App/UI/Theme.swift`

**Interfaces:**
- Consumes: `HRZone` (Task 1)
- Produces: `extension HRZone { var color: Color }`, `Theme.elapsedYellow`, `Theme.inactiveZoneOpacity`, `Theme.ringWidth`, `Theme.scaleWidth`

No tests: this is a table of constants. A test asserting a colour equals itself proves nothing.

- [ ] **Step 1: Write the implementation**

`FitBud Watch App/UI/Theme.swift`:
```swift
import SwiftUI

/// Zone colours live here rather than on `HRZone` because `HRZone` is held by
/// `WorkoutState`, which is held by `WorkoutEngine` — and the engine must stay
/// Foundation-only to remain testable without a UI.
extension HRZone {
    var color: Color {
        switch id {
        case "Z1": Color(red: 0.196, green: 0.678, blue: 0.902)  // #32ADE6 teal
        case "Z2": Color(red: 0.188, green: 0.820, blue: 0.345)  // #30D158 green
        case "Z3": Color(red: 0.776, green: 0.957, blue: 0.196)  // #C6F432 chartreuse
        case "Z4": Color(red: 1.000, green: 0.624, blue: 0.039)  // #FF9F0A orange
        case "Z5": Color(red: 1.000, green: 0.216, blue: 0.373)  // #FF375F red
        default: .gray
        }
    }
}

enum Theme {
    /// Apple uses yellow rather than white for elapsed time in the Workout app,
    /// which keeps the clock distinct from the metrics without adding chrome.
    static let elapsedYellow = Color(red: 1.0, green: 0.839, blue: 0.039) // #FFD60A

    /// Inactive zone segments. Dark enough to recede, bright enough to still
    /// read as a scale when the display is dimmed in always-on mode.
    static let inactiveZoneOpacity: Double = 0.22

    static let ringWidth: CGFloat = 14
    static let scaleWidth: CGFloat = 5
    /// Gap between the draining phase ring and the zone scale outside it.
    static let ringToScaleGap: CGFloat = 4
}
```

- [ ] **Step 2: Verify it compiles and tests still pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **86 tests**, no compile errors.

- [ ] **Step 3: Commit**

```bash
git add "FitBud Watch App/UI/Theme.swift"
git commit -m "feat: add zone palette and theme constants"
```

---

### Task 7: DEBUG demo recorder

**Files:**
- Create: `FitBud Watch App/Support/DemoWorkoutRecorder.swift`
- Modify: `FitBud Watch App/UI/StartView.swift`

**Interfaces:**
- Consumes: `WorkoutRecording`, `WorkoutConfiguration`, `LiveMetrics`, `Split`, `CompletedWorkout`
- Produces: `DemoWorkoutRecorder` (DEBUG only), and `WorkoutSessionModel.startDemo()` — added in this task

**This task exists to make every later task verifiable.** The simulator has no heart-rate sensor, so without a scripted heart rate the ring, the zone scale, the zone bar and the summary breakdown are all invisible and could not be checked by looking. The sweep runs 130 → 200 bpm so every zone is entered in turn.

Everything here is inside `#if DEBUG` and cannot ship.

- [ ] **Step 1: Write the demo recorder**

`FitBud Watch App/Support/DemoWorkoutRecorder.swift`:
```swift
#if DEBUG
import Foundation

/// A fake recorder that plays a scripted workout, for looking at the UI on a
/// simulator that has no heart-rate sensor.
///
/// The heart rate sweeps 130 → 200 bpm and back, so every zone is entered in
/// turn and the ring, scale and zone bar can all be seen doing their job.
/// Compiled out of release builds entirely.
@MainActor
final class DemoWorkoutRecorder: WorkoutRecording {
    private var continuation: AsyncThrowingStream<LiveMetrics, Error>.Continuation?
    private var task: Task<Void, Never>?
    private var elapsed: TimeInterval = 0
    private var distance: Double = 0
    private var isPaused = false

    /// Seconds of simulated workout per real second. The sweep covers all five
    /// zones in about half a minute of watching.
    private let timeScale: Double = 20

    func start(_ configuration: WorkoutConfiguration) async throws -> AsyncThrowingStream<LiveMetrics, Error> {
        let stream = AsyncThrowingStream<LiveMetrics, Error> { continuation in
            self.continuation = continuation
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !self.isPaused else { continue }
                self.elapsed += self.timeScale / 2
                // Roughly 9:00/km, the athlete's target easy pace.
                self.distance += (self.timeScale / 2) * (1000.0 / 540.0)
                self.continuation?.yield(
                    LiveMetrics(
                        elapsed: self.elapsed,
                        distanceMeters: self.distance,
                        heartRate: Self.scriptedHeartRate(at: self.elapsed),
                        activeEnergyKcal: self.elapsed * 0.16
                    )
                )
            }
        }
        return stream
    }

    /// Triangle wave from 130 to 200 bpm over a 20-minute period, so the needle
    /// climbs through every zone and comes back down.
    static func scriptedHeartRate(at elapsed: TimeInterval) -> Double {
        let period: Double = 1_200
        let position = elapsed.truncatingRemainder(dividingBy: period) / period
        let triangle = position < 0.5 ? position * 2 : (1 - position) * 2
        return 130 + triangle * 70
    }

    func pause() async throws { isPaused = true }
    func resume() async throws { isPaused = false }

    func end(splits: [Split]) async throws -> CompletedWorkout {
        task?.cancel()
        continuation?.finish()
        let end = Date()
        return CompletedWorkout(
            start: end.addingTimeInterval(-elapsed),
            end: end,
            duration: elapsed,
            distanceMeters: distance,
            activeEnergyKcal: elapsed * 0.16,
            averageHeartRate: 158,
            splits: splits
        )
    }
}
#endif
```

- [ ] **Step 2: Add a demo entry point to the session model**

Add to `WorkoutSessionModel` in `FitBud Watch App/UI/WorkoutSessionModel.swift`, after `start(_:)`:
```swift
#if DEBUG
    /// Starts a scripted workout against `DemoWorkoutRecorder` so the UI can be
    /// seen on a simulator, which has no heart-rate sensor. Debug builds only.
    func startDemo() async {
        recorder = DemoWorkoutRecorder()
        await start(.longRun5to1)
    }
#endif
```

For that assignment to compile, the stored recorder must become a `var`. Change:
```swift
    private let recorder: WorkoutRecording
```
to:
```swift
    private var recorder: WorkoutRecording
```

That is the only change to the declaration — no extra property is needed. Note this is the
sole reason `recorder` is mutable; nothing in release code reassigns it.

- [ ] **Step 3: Add the demo row to the start screen**

In `FitBud Watch App/UI/StartView.swift`, add inside the `List`, after the `NavigationLink`:
```swift
#if DEBUG
            Button("Demo run (scripted HR)") {
                Task { await model.startDemo() }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
#endif
```

- [ ] **Step 4: Verify the scripted heart rate covers every zone**

Add to `FitBud Watch AppTests/HRZoneTests.swift`:
```swift
#if DEBUG
struct DemoHeartRateScriptTests {
    @Test func theScriptedSweepVisitsEveryZone() {
        // If the demo never reaches Z5 the ring's red state can never be looked
        // at, and this task would not achieve what it exists for.
        var visited = Set<String>()
        for second in stride(from: 0.0, through: 1_200.0, by: 5.0) {
            let bpm = DemoWorkoutRecorder.scriptedHeartRate(at: second)
            if let zone = HRZone.zone(for: bpm) { visited.insert(zone.id) }
        }
        #expect(visited == ["Z1", "Z2", "Z3", "Z4", "Z5"])
    }
}
#endif
```

- [ ] **Step 5: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

- [ ] **Step 6: Launch and confirm the demo runs**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" -derivedDataPath build build 2>&1 | grep -E "error:|\*\* BUILD"
xcrun simctl install ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 "build/Build/Products/Debug-watchsimulator/FitBud Watch App.app"
xcrun simctl launch ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 mj.FitBud.watchkitapp
xcrun simctl io ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 screenshot /tmp/demo-start.png
```

**Read the screenshot.** Expected: the start list with a "Demo run (scripted HR)" row. Tap it (via `osascript -e 'tell application "System Events" to tell process "Simulator" to click at {x, y}'`, locating the window with `osascript` first), wait, and screenshot again — the current `LiveWorkoutView` should now show a changing heart rate rather than `-- bpm`. That is the proof this task worked; without it the remaining tasks cannot be verified.

- [ ] **Step 7: Commit**

```bash
git add "FitBud Watch App/Support/DemoWorkoutRecorder.swift" "FitBud Watch App/UI/WorkoutSessionModel.swift" "FitBud Watch App/UI/StartView.swift" "FitBud Watch AppTests/HRZoneTests.swift"
git commit -m "feat: add DEBUG demo recorder with scripted heart rate sweep"
```

---

### Task 8: Effort ring view and page

**Files:**
- Create: `FitBud Watch App/UI/EffortRingView.swift`
- Create: `FitBud Watch App/UI/EffortPage.swift`

**Interfaces:**
- Consumes: `EffortRingGeometry` (Task 2), `HRZone` + `.color` (Tasks 1, 6), `Theme` (Task 6), `WorkoutState.currentZone/heartRate/phaseRemainingFraction/runWalkPhase/phaseRemaining` (Task 4)
- Produces: `EffortRingView(heartRate:currentZone:phaseRemainingFraction:targetZoneID:)`, `EffortPage(model:)`

- [ ] **Step 1: Write the ring**

`FitBud Watch App/UI/EffortRingView.swift`:
```swift
import SwiftUI

/// The effort ring: a thick arc that drains over the current run/walk interval,
/// with the five-zone scale and a live heart-rate needle outside it.
///
/// Presentation only — every angle comes from `EffortRingGeometry`, which is
/// tested separately.
struct EffortRingView: View {
    let heartRate: Double?
    let currentZone: HRZone?
    /// 1 → 0 across the current run/walk phase. `nil` for unstructured runs,
    /// which draw a full ring in the current zone's colour instead.
    let phaseRemainingFraction: Double?
    /// The zone the session is *meant* to be in, from the plan. Marked on the
    /// scale so target and actual can be compared without reading numbers.
    let targetZoneID: String?

    private var ringColor: Color { currentZone?.color ?? .gray }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            let scaleRadius = min(rect.width, rect.height) / 2
            let ringRadius = scaleRadius - Theme.scaleWidth - Theme.ringToScaleGap

            drawZoneScale(in: &context, center: rect.center, radius: scaleRadius)
            drawPhaseRing(in: &context, center: rect.center, radius: ringRadius)
            if let heartRate {
                drawNeedle(in: &context, center: rect.center, radius: scaleRadius, heartRate: heartRate)
            }
        }
    }

    private func drawZoneScale(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for zone in HRZone.table {
            let arc = EffortRingGeometry.arc(for: zone)
            // A hair of padding so adjacent segments read as separate rungs.
            let path = Path { p in
                p.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(arc.start + 1),
                    endAngle: .degrees(arc.end - 1),
                    clockwise: false
                )
            }
            let isActive = zone.id == currentZone?.id
            context.stroke(
                path,
                with: .color(zone.color.opacity(isActive ? 1 : Theme.inactiveZoneOpacity)),
                style: StrokeStyle(lineWidth: Theme.scaleWidth, lineCap: .butt)
            )

            // The target zone gets a thin outline even when the athlete is not
            // in it, so "where I should be" stays visible while drifting.
            if zone.id == targetZoneID, !isActive {
                context.stroke(
                    path,
                    with: .color(zone.color.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .butt)
                )
            }
        }
    }

    private func drawPhaseRing(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let track = Path { p in
            p.addArc(
                center: center, radius: radius,
                startAngle: .degrees(EffortRingGeometry.startAngle),
                endAngle: .degrees(EffortRingGeometry.endAngle),
                clockwise: false
            )
        }
        context.stroke(
            track,
            with: .color(.white.opacity(0.10)),
            style: StrokeStyle(lineWidth: Theme.ringWidth, lineCap: .round)
        )

        let fraction = phaseRemainingFraction ?? 1
        guard fraction > 0 else { return }
        let fill = Path { p in
            p.addArc(
                center: center, radius: radius,
                startAngle: .degrees(EffortRingGeometry.startAngle),
                endAngle: .degrees(EffortRingGeometry.startAngle + EffortRingGeometry.sweep * fraction),
                clockwise: false
            )
        }
        context.stroke(
            fill,
            with: .color(ringColor),
            style: StrokeStyle(lineWidth: Theme.ringWidth, lineCap: .round)
        )
    }

    private func drawNeedle(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, heartRate: Double) {
        let angle = Angle.degrees(EffortRingGeometry.angle(forHeartRate: heartRate))
        let outer = center.offset(by: radius + 4, at: angle)
        let inner = center.offset(by: radius - Theme.scaleWidth - 2, at: angle)
        var path = Path()
        path.move(to: inner)
        path.addLine(to: outer)
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension CGPoint {
    func offset(by distance: CGFloat, at angle: Angle) -> CGPoint {
        CGPoint(
            x: x + distance * cos(angle.radians),
            y: y + distance * sin(angle.radians)
        )
    }
}
```

- [ ] **Step 2: Write the page**

`FitBud Watch App/UI/EffortPage.swift`:
```swift
import SwiftUI

/// Page 1, the default. Heart rate and zone at a glance, with the run/walk
/// interval draining around them.
struct EffortPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        ZStack {
            EffortRingView(
                heartRate: state.heartRate,
                currentZone: state.currentZone,
                phaseRemainingFraction: state.phaseRemainingFraction,
                targetZoneID: state.currentBlock?.zone
            )

            VStack(spacing: 0) {
                Text(state.heartRate.map { "\(Int($0))" } ?? "--")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(state.currentZone.map { "\($0.id) \($0.name.uppercased())" } ?? "NO ZONE")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.currentZone?.color ?? .secondary)

                if let phase = state.runWalkPhase, let remaining = state.phaseRemaining {
                    Text("\(phase == .run ? "RUN" : "WALK") \(formatPace(remaining))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .navigationTitle("Effort")
    }
}
```

- [ ] **Step 3: Temporarily render it so it can be seen**

`EffortPage` is not yet reachable — Task 11 wires the pages together. To verify now, change `RootView`'s `.running, .paused` case to `EffortPage(model: model)` **temporarily**, build, run the demo, and screenshot at several heart rates. Revert `RootView` before committing this task; Task 11 makes the change properly.

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" -derivedDataPath build build 2>&1 | grep -E "error:|\*\* BUILD"
xcrun simctl install ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 "build/Build/Products/Debug-watchsimulator/FitBud Watch App.app"
xcrun simctl launch ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 mj.FitBud.watchkitapp
# tap "Demo run", then screenshot repeatedly as the sweep climbs
xcrun simctl io ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 screenshot /tmp/ring-1.png
```

**Look at the screenshots and check all of:** the arc has a gap at the bottom, not a closed circle; exactly one zone segment is bright and it is the one matching the displayed zone name; the needle sits inside that bright segment; the thick ring is visibly shorter than a full 240° once the interval is partway through; the ring's colour matches the zone name's colour. Take at least three screenshots at different heart rates and confirm the bright segment and needle move together. Paste what you saw into your report.

- [ ] **Step 4: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/UI/EffortRingView.swift" "FitBud Watch App/UI/EffortPage.swift"
git commit -m "feat: add effort ring and effort page"
```

---

### Task 9: Zones page and zone breakdown bar

**Files:**
- Create: `FitBud Watch App/UI/ZoneBreakdownBar.swift`
- Create: `FitBud Watch App/UI/ZonesPage.swift`

**Interfaces:**
- Consumes: `zoneShares(timeInZone:)` + `ZoneShare` (Task 5), `HRZone.color` (Task 6), `WorkoutState` (Task 4), `formatDuration`/`formatPace`
- Produces: `ZoneBreakdownBar(timeInZone:)`, `ZonesPage(model:)`

This page follows Apple's layout: the five-segment bar with the **active segment widened** to carry its caption (unlike the ring, per the spec), then number-led rows with tiny labels to the right.

- [ ] **Step 1: Write the breakdown bar**

`FitBud Watch App/UI/ZoneBreakdownBar.swift`:
```swift
import SwiftUI

/// A stacked horizontal bar of time spent per zone. Shared by the Zones page
/// and the post-run summary, where it answers "did I actually keep it easy?"
struct ZoneBreakdownBar: View {
    let timeInZone: [String: TimeInterval]
    var height: CGFloat = 8

    private var shares: [ZoneShare] { zoneShares(timeInZone: timeInZone) }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(shares, id: \.zone.id) { share in
                    Rectangle()
                        .fill(share.zone.color)
                        .frame(width: max(1, geometry.size.width * share.fraction))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .overlay {
            if shares.isEmpty {
                Capsule().fill(.white.opacity(0.12))
            }
        }
    }
}
```

- [ ] **Step 2: Write the zones page**

`FitBud Watch App/UI/ZonesPage.swift`:
```swift
import SwiftUI

/// Page 2, in Apple's Heart Rate Zones idiom: the segmented ladder, then
/// number-led rows with tiny uppercase labels stacked to their right.
struct ZonesPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatDuration(state.elapsed))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.elapsedYellow)

            zoneLadder

            metric(
                value: state.heartRate.map { "\(Int($0))" } ?? "--",
                unit: "♥",
                label: nil
            )
            metric(
                value: formatDuration(state.timeInZone[state.currentZone?.id ?? ""] ?? 0),
                unit: nil,
                label: "TIME\nIN ZONE"
            )
            metric(
                value: state.averageHeartRate.map { "\(Int($0))" } ?? "--",
                unit: "BPM",
                label: "AVERAGE\nHR"
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Zones")
    }

    /// Five segments, with the active one widened to carry its caption — the
    /// ring cannot do this because widening would move its needle's frame of
    /// reference, but this bar has no needle to keep honest.
    private var zoneLadder: some View {
        HStack(spacing: 2) {
            ForEach(HRZone.table) { zone in
                let isActive = zone.id == state.currentZone?.id
                RoundedRectangle(cornerRadius: 3)
                    .fill(zone.color.opacity(isActive ? 1 : Theme.inactiveZoneOpacity))
                    .frame(height: 20)
                    .frame(maxWidth: isActive ? .infinity : 18)
                    .overlay {
                        if isActive {
                            Text("♥ \(zone.id)")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                        }
                    }
            }
        }
    }

    private func metric(value: String, unit: String?, label: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(unit == "♥" ? .red : .secondary)
            }
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineSpacing(-2)
            }
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 3: Verify by screenshot**

Temporarily point `RootView`'s `.running, .paused` case at `ZonesPage(model: model)`, build, install, run the demo, screenshot at three different heart rates, and revert `RootView` before committing (same procedure as Task 8, Step 3).

**Look at the screenshots and check:** exactly one segment is bright and widened, and it carries its `♥ Zn` caption in black; the other four are narrow and dim; elapsed is yellow; the numbers are large with tiny two-line labels to their right; nothing is clipped at the 46mm screen edges.

- [ ] **Step 4: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/UI/ZoneBreakdownBar.swift" "FitBud Watch App/UI/ZonesPage.swift"
git commit -m "feat: add zones page and zone breakdown bar"
```

---

### Task 10: Metrics, Splits and Controls pages

**Files:**
- Create: `FitBud Watch App/UI/MetricsPage.swift`
- Create: `FitBud Watch App/UI/SplitsPage.swift`
- Create: `FitBud Watch App/UI/ControlsPage.swift`

**Interfaces:**
- Consumes: `WorkoutState`, `Split.paceSecPerKm`/`heartRateAtSplit`, `formatDuration`, `formatPace`, `Theme`, `WorkoutSessionModel.pause()/resume()/end()/phase/errorMessage`
- Produces: `MetricsPage(model:)`, `SplitsPage(model:)`, `ControlsPage(model:)`

Grouped into one task because they share the same metric-row idiom and a reviewer would accept or reject them together.

- [ ] **Step 1: Write the metrics page**

`FitBud Watch App/UI/MetricsPage.swift`:
```swift
import SwiftUI

/// Page 3. The classic four numbers, number-led with labels to the right.
struct MetricsPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(formatDuration(state.elapsed))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.elapsedYellow)

            row(String(format: "%.2f", state.distanceKm), "KM")
            row(state.averagePaceSecPerKm.map(formatPace) ?? "--:--", "/KM")
            row("\(Int(state.activeEnergyKcal))", "KCAL")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Metrics")
    }

    private func row(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
```

- [ ] **Step 2: Write the splits page**

`FitBud Watch App/UI/SplitsPage.swift`:
```swift
import SwiftUI

/// Page 4. One row per completed kilometre, with a bar scaled to relative pace
/// so a fast or slow kilometre is visible without comparing numbers.
///
/// This is the only page allowed to scroll: split rows are unbounded, and a
/// scrolling child elsewhere would compete with the crown for paging.
struct SplitsPage: View {
    let model: WorkoutSessionModel

    private var splits: [Split] { model.state.splits }

    /// The slowest split sets the full bar width, so bars compare against the
    /// athlete's own kilometres rather than an arbitrary constant.
    private var slowestPace: Double {
        max(splits.map(\.paceSecPerKm).max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if splits.isEmpty {
                    Text("No splits yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(splits, id: \.index) { split in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(split.index)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(formatPace(split.paceSecPerKm))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            if let bpm = split.heartRateAtSplit {
                                Text("\(Int(bpm))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(paceColor(for: split))
                                .frame(width: geometry.size.width * (split.paceSecPerKm / slowestPace))
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Splits")
    }

    private func paceColor(for split: Split) -> Color {
        guard let bpm = split.heartRateAtSplit, let zone = HRZone.zone(for: bpm) else {
            return .white.opacity(0.4)
        }
        return zone.color
    }
}
```

- [ ] **Step 3: Write the controls page**

`FitBud Watch App/UI/ControlsPage.swift`:
```swift
import SwiftUI

/// Page 0, one crown turn *up* from Effort — the vertical analogue of Apple
/// putting workout controls to the left of the metrics.
struct ControlsPage: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(spacing: 10) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Button {
                Task {
                    model.phase == .paused ? await model.resume() : await model.pause()
                }
            } label: {
                Label(
                    model.phase == .paused ? "Resume" : "Pause",
                    systemImage: model.phase == .paused ? "play.fill" : "pause.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(.orange)

            Button {
                Task { await model.end() }
            } label: {
                Label("End", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .padding(.horizontal, 8)
        .navigationTitle("Controls")
    }
}
```

- [ ] **Step 4: Verify by screenshot**

Temporarily point `RootView` at each of the three pages in turn, build, install, run the demo, screenshot, and revert. **Check:** Metrics shows four values with elapsed in yellow; Splits shows rows with bars once the demo has covered a kilometre (the demo runs at 20× so this takes about 30 seconds) and shows "No splits yet" before that; Controls shows two full-width buttons that are not clipped.

- [ ] **Step 5: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/UI/MetricsPage.swift" "FitBud Watch App/UI/SplitsPage.swift" "FitBud Watch App/UI/ControlsPage.swift"
git commit -m "feat: add metrics, splits and controls pages"
```

---

### Task 11: Crown-paged LiveWorkoutView

**Files:**
- Modify: `FitBud Watch App/UI/LiveWorkoutView.swift` (replace its entire body)

**Interfaces:**
- Consumes: `ControlsPage`, `EffortPage`, `ZonesPage`, `MetricsPage`, `SplitsPage` (Tasks 8–10)
- Produces: the five-page crown-paged live screen

- [ ] **Step 1: Replace LiveWorkoutView**

`FitBud Watch App/UI/LiveWorkoutView.swift`:
```swift
import SwiftUI

/// The live workout screen: five pages driven by the Digital Crown.
///
/// Selection starts at `.effort`, so Controls sit one turn *up* and the data
/// pages fan out below — the vertical analogue of Apple placing controls to the
/// left of the metrics.
struct LiveWorkoutView: View {
    let model: WorkoutSessionModel

    private enum Page: Hashable {
        case controls, effort, zones, metrics, splits
    }

    @State private var page: Page = .effort

    var body: some View {
        TabView(selection: $page) {
            ControlsPage(model: model).tag(Page.controls)
            EffortPage(model: model).tag(Page.effort)
            ZonesPage(model: model).tag(Page.zones)
            MetricsPage(model: model).tag(Page.metrics)
            SplitsPage(model: model).tag(Page.splits)
        }
        .tabViewStyle(.verticalPage)
        .navigationBarBackButtonHidden(true)
    }
}
```

- [ ] **Step 2: Confirm the temporary RootView change from Tasks 8-10 is reverted**

Run: `grep -n "case .running" -A2 "FitBud Watch App/UI/RootView.swift"`
Expected: it renders `LiveWorkoutView(model: model)`, not any individual page. If a page is still wired in, restore it now.

- [ ] **Step 3: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

- [ ] **Step 4: Verify crown paging on the simulator**

Build, install, launch, start the demo run, then page with the crown and screenshot each page:
```bash
xcrun simctl io ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 screenshot /tmp/page-effort.png
```
The crown can be driven in the Simulator with the hardware keyboard once the window has focus, or by dragging the crown in the UI. Capture all five pages.

**Check:** Effort is the page you land on, not Controls; a page indicator appears on the right edge; each page has its own title; scrolling on Splits scrolls the list rather than changing page; nothing is clipped. Paste what you saw into your report — this is the task where the whole structure either works or doesn't.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/UI/LiveWorkoutView.swift"
git commit -m "feat: make the live workout screen crown-paged"
```

---

### Task 12: Start screen restyle

**Files:**
- Modify: `FitBud Watch App/UI/StartView.swift`

**Interfaces:**
- Consumes: `WorkoutConfiguration`, `WorkoutSessionModel`, `HistoryProbeView`
- Produces: restyled start screen

- [ ] **Step 1: Rewrite the body**

Replace the `List { … }` in `FitBud Watch App/UI/StartView.swift` with:
```swift
        List {
            // Above the session rows, not below them: on a 46mm screen only
            // about three rows are visible, so a refusal to start rendered at
            // the bottom is a message the athlete never sees.
            if let message = model.errorMessage ?? authorizationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(options, id: \.title) { option in
                Button {
                    Task { await model.start(option) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.title)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(subtitle(for: option))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listItemTint(.green)
            }

            NavigationLink("Health history probe") {
                HistoryProbeView()
            }
            .font(.footnote)

#if DEBUG
            Button("Demo run (scripted HR)") {
                Task { await model.startDemo() }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
#endif
        }
        .listStyle(.carousel)
        .navigationTitle("FitBud")
```

And add this helper to `StartView`:
```swift
    /// Spells out the run/walk ratio, so the two long-run options are
    /// distinguishable at a glance rather than by remembering which is which.
    private func subtitle(for configuration: WorkoutConfiguration) -> String {
        guard let runWalk = configuration.runWalk else { return "Continuous · Zone 2" }
        let run = Int(runWalk.runSeconds / 60)
        let walk = Int(runWalk.walkSeconds / 60)
        return "Run \(run) min · walk \(walk) min"
    }
```

- [ ] **Step 2: Run the tests and screenshot**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**.

Then build, install, launch, screenshot. **Check:** rows are full-width carousel cards with a title and a run/walk subtitle; the two long-run rows are now distinguishable; the probe and demo rows are visibly secondary.

- [ ] **Step 3: Commit**

```bash
git add "FitBud Watch App/UI/StartView.swift"
git commit -m "feat: restyle the start screen as carousel rows"
```

---

### Task 13: Summary with zone breakdown

**Files:**
- Modify: `FitBud Watch App/UI/SummaryView.swift`
- Modify: `FitBud Watch App/UI/WorkoutSessionModel.swift` (carry `timeInZone` into the summary)
- Modify: `FitBud Watch App/UI/RootView.swift` (pass it through)

**Interfaces:**
- Consumes: `ZoneBreakdownBar` (Task 9), `zoneShares` (Task 5), `CompletedWorkout`, `formatDuration`, `formatPace`
- Produces: `SummaryView(workout:timeInZone:errorMessage:onDone:)`

`CompletedWorkout` deliberately does not gain a `timeInZone` field: it mirrors what HealthKit saved, and zone time is our own derived measure. It is passed alongside instead.

- [ ] **Step 1: Keep zone time available after the workout ends**

In `WorkoutSessionModel`, add a stored property beside `state`:
```swift
    /// Zone time from the finished workout. `state` is cleared by `reset()`, but
    /// the summary still needs this after the run has ended.
    private(set) var finishedTimeInZone: [String: TimeInterval] = [:]
```

In `end()`, immediately after `let splits = state.splits`, add:
```swift
        finishedTimeInZone = state.timeInZone
```

In the `catch` branch of `end()` nothing more is needed — the assignment above already ran.

In `reset()`, add:
```swift
        finishedTimeInZone = [:]
```

- [ ] **Step 2: Pass it through RootView**

In `FitBud Watch App/UI/RootView.swift`, change the `.finished` case to:
```swift
            case let .finished(workout):
                SummaryView(
                    workout: workout,
                    timeInZone: model.finishedTimeInZone,
                    errorMessage: model.errorMessage,
                    onDone: { model.reset() }
                )
```

- [ ] **Step 3: Rewrite SummaryView**

`FitBud Watch App/UI/SummaryView.swift`:
```swift
import SwiftUI

struct SummaryView: View {
    let workout: CompletedWorkout
    /// Seconds per zone, keyed by `HRZone.id`. Ours, not HealthKit's.
    let timeInZone: [String: TimeInterval]
    /// Non-nil when the run could not be saved to HealthKit. The numbers below
    /// are then reconstructed from live state rather than read back from Health.
    let errorMessage: String?
    let onDone: () -> Void

    private var shares: [ZoneShare] { zoneShares(timeInZone: timeInZone) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: -2) {
                    Text(String(format: "%.2f", workout.distanceMeters / 1000))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("KILOMETRES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(formatDuration(workout.duration))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.elapsedYellow)

                if !shares.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TIME IN ZONE")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ZoneBreakdownBar(timeInZone: timeInZone, height: 10)
                        ForEach(shares, id: \.zone.id) { share in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(share.zone.color)
                                    .frame(width: 7, height: 7)
                                Text(share.zone.id)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(formatDuration(share.seconds))
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text("\(Int((share.fraction * 100).rounded()))%")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                statRow("Avg pace", workout.averagePaceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
                statRow("Avg HR", workout.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
                statRow("Energy", "\(Int(workout.activeEnergyKcal)) kcal")

                if !workout.splits.isEmpty {
                    Text("SPLITS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(workout.splits, id: \.index) { split in
                        VStack(alignment: .leading, spacing: 2) {
                            statRow("km \(split.index)", formatPace(split.paceSecPerKm))
                            // Bars scaled against the athlete's own slowest
                            // kilometre, so a fade or a surge is visible without
                            // comparing six numbers to each other.
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(splitColor(split))
                                    .frame(width: geometry.size.width * (split.paceSecPerKm / slowestPace))
                            }
                            .frame(height: 3)
                        }
                    }
                }

                Button("New run", action: onDone)
                    .font(.footnote)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Done")
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    /// The slowest split sets the full bar width.
    private var slowestPace: Double {
        max(workout.splits.map(\.paceSecPerKm).max() ?? 1, 1)
    }

    /// Colour each split by the zone its heart rate landed in, so the split list
    /// doubles as a record of where the effort went.
    private func splitColor(_ split: Split) -> Color {
        guard let bpm = split.heartRateAtSplit, let zone = HRZone.zone(for: bpm) else {
            return .white.opacity(0.35)
        }
        return zone.color
    }
}
```

Note the "New run" button has moved to the **bottom** here, because this view now scrolls and leads with the numbers the athlete opened it to read. It was at the top previously to keep it reachable past unbounded split rows; a scrolling container makes that unnecessary, and the run summary is what should greet you.

- [ ] **Step 4: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **87 tests**. If `WorkoutSessionModelTests` fails to compile, it is constructing `SummaryView` — update those call sites for the new `timeInZone:` parameter.

- [ ] **Step 5: Verify by screenshot**

Build, install, launch, run the demo for about a minute so several zones and a kilometre or two accumulate, then end it via the Controls page.

**Check:** distance is the hero number; duration is yellow beneath it; the zone bar shows several coloured segments matching the zones the demo swept; the percentages sum to 100; splits are listed; "New run" returns to the start screen.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/UI/SummaryView.swift" "FitBud Watch App/UI/WorkoutSessionModel.swift" "FitBud Watch App/UI/RootView.swift"
git commit -m "feat: add zone breakdown to the workout summary"
```

---

## Definition of done

- [ ] `xcodebuild … test` reports `** TEST SUCCEEDED **` with **87 tests**
- [ ] All five live pages reachable by crown, landing on Effort
- [ ] The effort ring's bright zone segment, needle and ring colour agree with each other at three or more different heart rates, confirmed by screenshot
- [ ] The zones page widens exactly one segment and captions it
- [ ] The summary's zone breakdown percentages sum to 100 after a demo run
- [ ] Nothing clipped at 46mm on any page
- [ ] `HealthKitWorkoutRecorder.swift` and `WorkoutRecording.swift` are untouched — confirm with `git diff --stat` over the whole branch
- [ ] `project.pbxproj` is unchanged by every commit
- [ ] Verified on the real Series 10 with real heart rate — the one thing the simulator cannot do

## Out of scope

Per spec §9: Activity rings (Move/Exercise/Stand), cadence, stride length, ground contact time, vertical oscillation, running power, elevation, media controls, and user-reorderable views. Zone-crossing haptics are deliberately deferred until hysteresis can be tuned against real running data (spec §10.1).
