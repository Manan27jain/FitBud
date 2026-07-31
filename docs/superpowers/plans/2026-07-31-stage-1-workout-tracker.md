# FitBud Stage 1 — Workout Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A watchOS app that reliably tracks a run — heart rate, distance, pace, splits, energy — conducts structured segment and run/walk sessions with haptics, saves to HealthKit, and answers how far back watchOS can query health history.

**Architecture:** Pure logic (`SegmentTimeline`, `SplitDetector`, `RunWalkCycler`, `WorkoutEngine`) is fully separated from HealthKit. The engine consumes a stream of `LiveMetrics` snapshots and emits `WorkoutEvent`s; it never imports HealthKit. `HealthKitWorkoutRecorder` sits behind the `WorkoutRecording` protocol and is the only type that touches `HKWorkoutSession`. Tests target the pure layer with synthetic metric streams — no mocking framework, no simulator dependency.

**Tech Stack:** Swift 5, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), HealthKit, watchOS 11.2.

## Global Constraints

- Deployment target: **watchOS 11.2**. Swift version: **5.0**.
- Test module: `@testable import FitBud_Watch_App` (underscores, not spaces).
- Test framework is **Swift Testing**, not XCTest. Use `@Test` / `#expect`, never `XCTAssert`.
- Build/test command (both verified working):
  `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test`
- Simulator: Apple Watch SE (44mm, 2nd gen), UUID `BF994011-AC8D-4857-BEFF-F2AD01567CAA`.
- The project uses **Xcode 16 synchronized folder groups** (`objectVersion = 77`). New `.swift` files placed in `FitBud Watch App/` or `FitBud Watch AppTests/` are compiled automatically — **never edit `project.pbxproj` to add a source file.** (Build *settings* changes in Task 7 do require a pbxproj edit; that is the only one.)
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`). Plist keys are set as `INFOPLIST_KEY_*` build settings, not by creating an Info.plist file.
- Bundle identifier: `mj.FitBud.watchkitapp`. Development team: `2B29LY8MNV`.
- **No AI, no networking, no plan-JSON consumption in Stage 1.** Those are Stages 2–4.
- Units: metric. Distances in **meters** internally, displayed as km. Pace in **seconds per km**.
- Every task ends green: the full test suite passes before committing.

## File Structure

```
FitBud Watch App/
  FitBudApp.swift                     MODIFY — root scene points at RootView
  Models/
    LiveMetrics.swift                 Immutable snapshot of live sensor values
    WorkoutSegment.swift              Session shape (warmup/repeat/cooldown/open)
    Split.swift                       One completed kilometre
    WorkoutState.swift                Everything the UI renders
    CompletedWorkout.swift            Post-run summary
    WorkoutConfiguration.swift        What to record (Stage 2 maps PlanDay -> this)
  Engine/
    SegmentTimeline.swift             Flattens segments into ordered blocks (pure)
    SplitDetector.swift               Detects km boundaries (pure)
    RunWalkCycler.swift               Run/walk phase from elapsed (pure, stateless)
    WorkoutEngine.swift               Composes the above, emits events (pure)
  Health/
    WorkoutRecording.swift            Protocol — the seam HealthKit hides behind
    HealthAuthorization.swift         Permission request + status
    HealthKitWorkoutRecorder.swift    HKWorkoutSession + HKLiveWorkoutBuilder
    HealthHistoryProbe.swift          Spec §12.1 spike
  Support/
    HapticPlaying.swift               Protocol + WKInterfaceDevice implementation
  UI/
    RootView.swift                    Navigation
    StartView.swift                   Pick a session, request permission
    LiveWorkoutView.swift             During-run display
    SummaryView.swift                 Post-run summary
    HistoryProbeView.swift            §12.1 results
  FitBud Watch App.entitlements       NEW — HealthKit entitlement

FitBud Watch AppTests/
  SplitDetectorTests.swift
  RunWalkCyclerTests.swift
  SegmentTimelineTests.swift
  WorkoutEngineTests.swift
```

`ContentView.swift` is deleted in Task 12 once `RootView` replaces it.

---

### Task 1: Toolchain — shared scheme and a green baseline

**Status: the scheme file is already written and verified.** This task commits it.

**Files:**
- Create: `FitBud.xcodeproj/xcshareddata/xcschemes/FitBud Watch App.xcscheme` *(already exists)*

**Interfaces:**
- Consumes: nothing
- Produces: a working `xcodebuild ... test` invocation every later task depends on

**Background:** The auto-generated scheme included the `FitBud` iOS target (product type `application.watchapp2-container`, a vestigial App Store wrapper). Building it requires an iOS simulator runtime, which is not installed, so *every* `-scheme` build and test failed with `No available simulator runtimes for platform iphonesimulator`. The shared scheme references only the watch app and its unit-test bundle.

- [ ] **Step 1: Confirm the shared scheme exists and excludes the iOS target**

Run: `grep -c "2D91C715301D054F00AA9A85" "FitBud.xcodeproj/xcshareddata/xcschemes/FitBud Watch App.xcscheme"`
Expected: `0` — the iOS container target UUID must not appear.

- [ ] **Step 2: Run the test suite to confirm a green baseline**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: `** TEST SUCCEEDED **` and the template's `example()` test passing.

- [ ] **Step 3: Commit**

```bash
git add "FitBud.xcodeproj/xcshareddata/xcschemes/FitBud Watch App.xcscheme"
git commit -m "build: add shared watch-only scheme so build and test work

The autogenerated scheme pulled in the vestigial iOS container target,
which needs an iOS simulator runtime that is not installed. Both build
and test failed as a result."
```

---

### Task 2: Core value types

**Files:**
- Create: `FitBud Watch App/Models/LiveMetrics.swift`
- Create: `FitBud Watch App/Models/Split.swift`
- Create: `FitBud Watch App/Models/WorkoutSegment.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `LiveMetrics(elapsed:distanceMeters:heartRate:activeEnergyKcal:)`, `Split(index:distanceMeters:elapsed:duration:averageHeartRate:)`, `WorkoutSegment` enum with `.warmup/.cooldown/.repeatBlock/.openEnded`, `Interval(minutes:zone:label:)`, and `Split.paceSecPerKm`

These are plain data with no behaviour beyond one derived property, so they carry a single test for that property rather than a full TDD cycle each.

- [ ] **Step 1: Write the value types**

`FitBud Watch App/Models/LiveMetrics.swift`:
```swift
import Foundation

/// An immutable snapshot of sensor values at one instant of a workout.
/// Produced by `WorkoutRecording`, consumed by `WorkoutEngine`.
struct LiveMetrics: Equatable, Sendable {
    /// Seconds since the workout started, excluding time spent paused.
    var elapsed: TimeInterval
    var distanceMeters: Double
    /// `nil` until the first heart-rate sample arrives.
    var heartRate: Double?
    var activeEnergyKcal: Double

    init(
        elapsed: TimeInterval,
        distanceMeters: Double = 0,
        heartRate: Double? = nil,
        activeEnergyKcal: Double = 0
    ) {
        self.elapsed = elapsed
        self.distanceMeters = distanceMeters
        self.heartRate = heartRate
        self.activeEnergyKcal = activeEnergyKcal
    }
}
```

`FitBud Watch App/Models/Split.swift`:
```swift
import Foundation

/// One completed kilometre.
struct Split: Equatable, Sendable {
    /// 1-based: the first kilometre is index 1.
    let index: Int
    let distanceMeters: Double
    /// Cumulative elapsed time at the moment this split completed.
    let elapsed: TimeInterval
    /// Time taken for this split alone.
    let duration: TimeInterval
    let averageHeartRate: Double?

    /// Pace for this split in seconds per kilometre.
    var paceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return duration / (distanceMeters / 1000)
    }
}
```

`FitBud Watch App/Models/WorkoutSegment.swift`:
```swift
import Foundation

/// One work or recovery period inside a repeat block.
struct Interval: Equatable, Sendable {
    let minutes: Double
    let zone: String
    let label: String

    init(minutes: Double, zone: String, label: String = "") {
        self.minutes = minutes
        self.zone = zone
        self.label = label
    }
}

/// The shape of a session. Mirrors the `segments` array in the plan JSON,
/// which Stage 2 will decode directly into this type.
enum WorkoutSegment: Equatable, Sendable {
    case warmup(minutes: Double, zone: String, label: String)
    case cooldown(minutes: Double, zone: String, label: String)
    case repeatBlock(times: Int, work: Interval, recover: Interval)
    /// Easy and long runs have no structure — they run until you stop.
    case openEnded(zone: String, label: String)
}
```

- [ ] **Step 2: Write a test for the one piece of behaviour**

`FitBud Watch AppTests/SplitDetectorTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct SplitPaceTests {
    @Test func paceIsSecondsPerKilometre() {
        let split = Split(
            index: 1,
            distanceMeters: 1000,
            elapsed: 540,
            duration: 540,
            averageHeartRate: 155
        )
        #expect(split.paceSecPerKm == 540)
    }

    @Test func paceIsZeroForZeroDistance() {
        let split = Split(index: 1, distanceMeters: 0, elapsed: 10, duration: 10, averageHeartRate: nil)
        #expect(split.paceSecPerKm == 0)
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — 3 tests (template `example()` plus the two above).

- [ ] **Step 4: Commit**

```bash
git add "FitBud Watch App/Models" "FitBud Watch AppTests/SplitDetectorTests.swift"
git commit -m "feat: add core workout value types"
```

---

### Task 3: SplitDetector

**Files:**
- Create: `FitBud Watch App/Engine/SplitDetector.swift`
- Test: `FitBud Watch AppTests/SplitDetectorTests.swift` (append to the file from Task 2)

**Interfaces:**
- Consumes: `Split` from Task 2
- Produces: `SplitDetector(intervalMeters:)`, `mutating func update(distanceMeters:elapsed:heartRate:) -> [Split]`, `var splits: [Split]`

`update` returns an **array** because a single GPS update can cross more than one kilometre boundary — a stale-then-jumping distance reading is common on a watch, and dropping the intermediate split would silently lose data.

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/SplitDetectorTests.swift`:
```swift
struct SplitDetectorTests {
    @Test func noSplitBeforeFirstKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        #expect(detector.update(distanceMeters: 999, elapsed: 500, heartRate: 150).isEmpty)
        #expect(detector.splits.isEmpty)
    }

    @Test func splitFiresAtExactlyOneKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        #expect(splits.count == 1)
        #expect(splits[0].index == 1)
        #expect(splits[0].duration == 540)
        #expect(splits[0].elapsed == 540)
    }

    @Test func splitDurationIsTimeSinceTheLastSplit() {
        var detector = SplitDetector(intervalMeters: 1000)
        _ = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        let second = detector.update(distanceMeters: 2000, elapsed: 1100, heartRate: 158)
        #expect(second.count == 1)
        #expect(second[0].index == 2)
        #expect(second[0].duration == 560)
        #expect(second[0].elapsed == 1100)
    }

    @Test func splitDoesNotRepeatWhileInsideTheSameKilometre() {
        var detector = SplitDetector(intervalMeters: 1000)
        _ = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 150)
        #expect(detector.update(distanceMeters: 1400, elapsed: 760, heartRate: 152).isEmpty)
        #expect(detector.splits.count == 1)
    }

    @Test func aDistanceJumpEmitsEverySplitItCrossed() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 2100, elapsed: 1100, heartRate: 150)
        #expect(splits.count == 2)
        #expect(splits.map(\.index) == [1, 2])
        #expect(detector.splits.count == 2)
    }

    @Test func heartRateIsCarriedOntoTheSplit() {
        var detector = SplitDetector(intervalMeters: 1000)
        let splits = detector.update(distanceMeters: 1000, elapsed: 540, heartRate: 162)
        #expect(splits[0].averageHeartRate == 162)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'SplitDetector' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Engine/SplitDetector.swift`:
```swift
import Foundation

/// Detects kilometre boundaries in a monotonically increasing distance stream.
/// Pure: no clock, no sensors, no HealthKit.
struct SplitDetector {
    let intervalMeters: Double

    private(set) var splits: [Split] = []
    private var lastSplitElapsed: TimeInterval = 0

    init(intervalMeters: Double = 1000) {
        self.intervalMeters = intervalMeters
    }

    /// Feeds the latest cumulative distance in.
    /// Returns every split completed by this update, in order — usually none or one,
    /// but more if the distance reading jumped across several boundaries at once.
    mutating func update(
        distanceMeters: Double,
        elapsed: TimeInterval,
        heartRate: Double?
    ) -> [Split] {
        let completed = Int(distanceMeters / intervalMeters)
        guard completed > splits.count else { return [] }

        var emitted: [Split] = []
        // Interpolate evenly across the boundaries this update crossed. With a
        // single boundary this is exact; with several it apportions the elapsed
        // time between them, which is the best available estimate.
        let spanStart = lastSplitElapsed
        let spanDuration = elapsed - spanStart
        let crossings = completed - splits.count

        for step in 1...crossings {
            let splitElapsed = spanStart + spanDuration * (Double(step) / Double(crossings))
            let index = splits.count + 1
            let split = Split(
                index: index,
                distanceMeters: intervalMeters,
                elapsed: splitElapsed,
                duration: splitElapsed - lastSplitElapsed,
                averageHeartRate: heartRate
            )
            splits.append(split)
            emitted.append(split)
            lastSplitElapsed = splitElapsed
        }
        return emitted
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 9 tests.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Engine/SplitDetector.swift" "FitBud Watch AppTests/SplitDetectorTests.swift"
git commit -m "feat: add SplitDetector with multi-boundary handling"
```

---

### Task 4: RunWalkCycler

**Files:**
- Create: `FitBud Watch App/Engine/RunWalkCycler.swift`
- Test: `FitBud Watch AppTests/RunWalkCyclerTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `RunWalkPhase` enum (`.run`, `.walk`), `RunWalkCycler(runSeconds:walkSeconds:)`, `func phase(at:) -> RunWalkPhase`, `func remainingInPhase(at:) -> TimeInterval`

Deliberately **stateless** — phase is a pure function of elapsed time. That makes it immune to dropped or bunched updates, and it means transition detection (which needs memory) lives in `WorkoutEngine` where the rest of the state already is. The plan uses 4:1 (240s/60s) in weeks 1–4 and 5:1 (300s/60s) from week 5.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/RunWalkCyclerTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct RunWalkCyclerTests {
    let fourToOne = RunWalkCycler(runSeconds: 240, walkSeconds: 60)

    @Test func startsRunning() {
        #expect(fourToOne.phase(at: 0) == .run)
    }

    @Test func stillRunningJustBeforeTheSwitch() {
        #expect(fourToOne.phase(at: 239) == .run)
    }

    @Test func walksAtTheEndOfTheRunInterval() {
        #expect(fourToOne.phase(at: 240) == .walk)
    }

    @Test func returnsToRunningAtTheEndOfTheCycle() {
        #expect(fourToOne.phase(at: 300) == .run)
    }

    @Test func cyclesRepeatedly() {
        // Fourth cycle: 900s in is a run, 1140s in is a walk.
        #expect(fourToOne.phase(at: 900) == .run)
        #expect(fourToOne.phase(at: 1140) == .walk)
    }

    @Test func reportsTimeLeftInTheCurrentPhase() {
        #expect(fourToOne.remainingInPhase(at: 0) == 240)
        #expect(fourToOne.remainingInPhase(at: 100) == 140)
        #expect(fourToOne.remainingInPhase(at: 240) == 60)
        #expect(fourToOne.remainingInPhase(at: 280) == 20)
    }

    @Test func fiveToOneRatioUsedFromWeekFive() {
        let fiveToOne = RunWalkCycler(runSeconds: 300, walkSeconds: 60)
        #expect(fiveToOne.phase(at: 299) == .run)
        #expect(fiveToOne.phase(at: 300) == .walk)
        #expect(fiveToOne.phase(at: 360) == .run)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'RunWalkCycler' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Engine/RunWalkCycler.swift`:
```swift
import Foundation

enum RunWalkPhase: Equatable, Sendable {
    case run
    case walk
}

/// Run/walk intervals expressed as a pure function of elapsed time.
///
/// Stateless by design: a dropped or delayed update can never desynchronise the
/// cycle, because the phase is always recomputed from the clock rather than
/// advanced step by step.
struct RunWalkCycler: Equatable, Sendable {
    let runSeconds: TimeInterval
    let walkSeconds: TimeInterval

    var cycleSeconds: TimeInterval { runSeconds + walkSeconds }

    func phase(at elapsed: TimeInterval) -> RunWalkPhase {
        positionInCycle(at: elapsed) < runSeconds ? .run : .walk
    }

    func remainingInPhase(at elapsed: TimeInterval) -> TimeInterval {
        let position = positionInCycle(at: elapsed)
        return position < runSeconds ? runSeconds - position : cycleSeconds - position
    }

    private func positionInCycle(at elapsed: TimeInterval) -> TimeInterval {
        guard cycleSeconds > 0 else { return 0 }
        return elapsed.truncatingRemainder(dividingBy: cycleSeconds)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 16 tests.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Engine/RunWalkCycler.swift" "FitBud Watch AppTests/RunWalkCyclerTests.swift"
git commit -m "feat: add stateless RunWalkCycler"
```

---

### Task 5: SegmentTimeline

**Files:**
- Create: `FitBud Watch App/Engine/SegmentTimeline.swift`
- Test: `FitBud Watch AppTests/SegmentTimelineTests.swift`

**Interfaces:**
- Consumes: `WorkoutSegment`, `Interval` from Task 2
- Produces: `BlockKind` enum (`.warmup/.work/.recover/.cooldown/.open`), `TimelineBlock(kind:duration:zone:label:)`, `SegmentTimeline(segments:)`, `var blocks: [TimelineBlock]`, `var totalDuration: TimeInterval?`, `func position(at:) -> SegmentTimeline.Position?`, `struct Position { index, block, remaining }`

Flattens `5 × (3min work / 2min recover)` into ten discrete blocks so the engine can index them directly. Interval sessions in the plan look exactly like this.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/SegmentTimelineTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct SegmentTimelineTests {
    /// Week 5 Thursday: 10min warmup, 5x(3min Z4 / 2min jog), 10min cooldown.
    let intervals = SegmentTimeline(segments: [
        .warmup(minutes: 10, zone: "Z1", label: "Warm up"),
        .repeatBlock(
            times: 5,
            work: Interval(minutes: 3, zone: "Z4", label: "3min threshold"),
            recover: Interval(minutes: 2, zone: "Z1", label: "2min jog")
        ),
        .cooldown(minutes: 10, zone: "Z1", label: "Cool down")
    ])

    @Test func repeatBlocksAreFlattenedIntoDiscreteBlocks() {
        // warmup + (work + recover) * 5 + cooldown
        #expect(intervals.blocks.count == 12)
        #expect(intervals.blocks[0].kind == .warmup)
        #expect(intervals.blocks[1].kind == .work)
        #expect(intervals.blocks[2].kind == .recover)
        #expect(intervals.blocks[10].kind == .recover)
        #expect(intervals.blocks[11].kind == .cooldown)
    }

    @Test func totalDurationSumsEveryBlock() {
        // 10 + 5*(3+2) + 10 = 45 minutes
        #expect(intervals.totalDuration == 45 * 60)
    }

    @Test func positionResolvesToTheWarmupAtTheStart() {
        let position = intervals.position(at: 0)
        #expect(position?.index == 0)
        #expect(position?.block.kind == .warmup)
        #expect(position?.remaining == 600)
    }

    @Test func positionCrossesIntoTheFirstWorkInterval() {
        let position = intervals.position(at: 600)
        #expect(position?.index == 1)
        #expect(position?.block.kind == .work)
        #expect(position?.block.zone == "Z4")
        #expect(position?.remaining == 180)
    }

    @Test func positionResolvesMidWorkout() {
        // 600 warmup + 180 work + 120 recover = 900s -> second work interval
        let position = intervals.position(at: 900)
        #expect(position?.index == 3)
        #expect(position?.block.kind == .work)
    }

    @Test func positionIsNilPastTheEnd() {
        #expect(intervals.position(at: 45 * 60 + 1) == nil)
    }

    @Test func openEndedSessionsHaveOneBlockAndNoTotalDuration() {
        let easy = SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy run")])
        #expect(easy.blocks.count == 1)
        #expect(easy.blocks[0].kind == .open)
        #expect(easy.blocks[0].duration == nil)
        #expect(easy.totalDuration == nil)
    }

    @Test func openEndedPositionNeverExpires() {
        let easy = SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy run")])
        let position = easy.position(at: 9_999)
        #expect(position?.index == 0)
        #expect(position?.remaining == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'SegmentTimeline' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Engine/SegmentTimeline.swift`:
```swift
import Foundation

enum BlockKind: Equatable, Sendable {
    case warmup
    case work
    case recover
    case cooldown
    /// Runs until the athlete stops. Has no duration.
    case open
}

/// One concrete, indivisible period of a session.
struct TimelineBlock: Equatable, Sendable {
    let kind: BlockKind
    /// `nil` for open-ended blocks.
    let duration: TimeInterval?
    let zone: String
    let label: String
}

/// Flattens a session's segments into an ordered list of blocks the engine can
/// index by elapsed time. A repeat block becomes its expanded repetitions.
struct SegmentTimeline: Equatable, Sendable {
    struct Position: Equatable {
        let index: Int
        let block: TimelineBlock
        /// `nil` when the block is open-ended.
        let remaining: TimeInterval?
    }

    let blocks: [TimelineBlock]

    init(segments: [WorkoutSegment]) {
        var blocks: [TimelineBlock] = []
        for segment in segments {
            switch segment {
            case let .warmup(minutes, zone, label):
                blocks.append(TimelineBlock(kind: .warmup, duration: minutes * 60, zone: zone, label: label))
            case let .cooldown(minutes, zone, label):
                blocks.append(TimelineBlock(kind: .cooldown, duration: minutes * 60, zone: zone, label: label))
            case let .repeatBlock(times, work, recover):
                for _ in 0..<times {
                    blocks.append(TimelineBlock(kind: .work, duration: work.minutes * 60, zone: work.zone, label: work.label))
                    blocks.append(TimelineBlock(kind: .recover, duration: recover.minutes * 60, zone: recover.zone, label: recover.label))
                }
            case let .openEnded(zone, label):
                blocks.append(TimelineBlock(kind: .open, duration: nil, zone: zone, label: label))
            }
        }
        self.blocks = blocks
    }

    /// `nil` if any block is open-ended — such a session has no fixed length.
    var totalDuration: TimeInterval? {
        var total: TimeInterval = 0
        for block in blocks {
            guard let duration = block.duration else { return nil }
            total += duration
        }
        return total
    }

    /// Which block the workout is in at `elapsed`, and how much of it is left.
    /// Returns `nil` once a fixed-length session has finished.
    func position(at elapsed: TimeInterval) -> Position? {
        var start: TimeInterval = 0
        for (index, block) in blocks.enumerated() {
            guard let duration = block.duration else {
                return Position(index: index, block: block, remaining: nil)
            }
            let end = start + duration
            if elapsed < end {
                return Position(index: index, block: block, remaining: end - elapsed)
            }
            start = end
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 24 tests.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Engine/SegmentTimeline.swift" "FitBud Watch AppTests/SegmentTimelineTests.swift"
git commit -m "feat: add SegmentTimeline flattening repeat blocks"
```

---

### Task 6: WorkoutEngine

**Files:**
- Create: `FitBud Watch App/Models/WorkoutState.swift`
- Create: `FitBud Watch App/Engine/WorkoutEngine.swift`
- Test: `FitBud Watch AppTests/WorkoutEngineTests.swift`

**Interfaces:**
- Consumes: `LiveMetrics`, `Split`, `SplitDetector`, `SegmentTimeline`, `TimelineBlock`, `RunWalkCycler`, `RunWalkPhase`
- Produces: `WorkoutEvent` enum (`.splitCompleted(Split)`, `.phaseChanged(RunWalkPhase)`, `.blockChanged(index:block:)`, `.finished`), `WorkoutState`, `WorkoutEngine(timeline:runWalk:)`, `mutating func ingest(_:) -> [WorkoutEvent]`, `var state: WorkoutState`

This is the heart of Stage 1 and the piece most worth testing. It stays pure: given the same sequence of `LiveMetrics`, it always produces the same events.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/WorkoutEngineTests.swift`:
```swift
import Testing
@testable import FitBud_Watch_App

struct WorkoutEngineTests {
    /// A long run: open-ended, 4:1 run/walk.
    private func longRunEngine() -> WorkoutEngine {
        WorkoutEngine(
            timeline: SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Long run")]),
            runWalk: RunWalkCycler(runSeconds: 240, walkSeconds: 60)
        )
    }

    @Test func firstUpdateAnnouncesTheStartingBlock() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 0))
        #expect(events.contains { if case .blockChanged(0, _) = $0 { return true }; return false })
    }

    @Test func stateTracksTheLatestMetrics() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 60, distanceMeters: 180, heartRate: 152, activeEnergyKcal: 14))
        #expect(engine.state.elapsed == 60)
        #expect(engine.state.distanceMeters == 180)
        #expect(engine.state.heartRate == 152)
        #expect(engine.state.activeEnergyKcal == 14)
    }

    @Test func emitsPhaseChangeWhenTheWalkBreakStarts() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 239, distanceMeters: 700))
        let events = engine.ingest(LiveMetrics(elapsed: 241, distanceMeters: 705))
        #expect(events.contains(.phaseChanged(.walk)))
        #expect(engine.state.runWalkPhase == .walk)
    }

    @Test func doesNotRepeatThePhaseChangeWithinTheSamePhase() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 241, distanceMeters: 705))
        let events = engine.ingest(LiveMetrics(elapsed: 250, distanceMeters: 720))
        #expect(!events.contains(.phaseChanged(.walk)))
    }

    @Test func emitsSplitWhenAKilometreCompletes() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 540, distanceMeters: 1000, heartRate: 158))
        let splits = events.compactMap { event -> Split? in
            if case let .splitCompleted(split) = event { return split }
            return nil
        }
        #expect(splits.count == 1)
        #expect(splits[0].index == 1)
        #expect(engine.state.splits.count == 1)
    }

    @Test func averagePaceIsDerivedFromElapsedAndDistance() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 540, distanceMeters: 1000))
        #expect(engine.state.averagePaceSecPerKm == 540)
    }

    @Test func averagePaceIsNilBeforeAnyDistance() {
        var engine = longRunEngine()
        _ = engine.ingest(LiveMetrics(elapsed: 10, distanceMeters: 0))
        #expect(engine.state.averagePaceSecPerKm == nil)
    }

    @Test func structuredSessionAdvancesThroughItsBlocks() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [
                .warmup(minutes: 10, zone: "Z1", label: "Warm up"),
                .repeatBlock(
                    times: 2,
                    work: Interval(minutes: 3, zone: "Z4", label: "Threshold"),
                    recover: Interval(minutes: 2, zone: "Z1", label: "Jog")
                ),
                .cooldown(minutes: 10, zone: "Z1", label: "Cool down")
            ]),
            runWalk: nil
        )
        _ = engine.ingest(LiveMetrics(elapsed: 0))
        let intoWork = engine.ingest(LiveMetrics(elapsed: 601))
        #expect(intoWork.contains { if case .blockChanged(1, _) = $0 { return true }; return false })
        #expect(engine.state.currentBlock?.kind == .work)
    }

    @Test func structuredSessionFinishesAfterItsLastBlock() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [.warmup(minutes: 1, zone: "Z1", label: "Warm up")]),
            runWalk: nil
        )
        _ = engine.ingest(LiveMetrics(elapsed: 0))
        let events = engine.ingest(LiveMetrics(elapsed: 61))
        #expect(events.contains(.finished))
        #expect(engine.state.isComplete)
    }

    @Test func openEndedSessionNeverFinishesOnItsOwn() {
        var engine = longRunEngine()
        let events = engine.ingest(LiveMetrics(elapsed: 7_200, distanceMeters: 14_000))
        #expect(!events.contains(.finished))
        #expect(!engine.state.isComplete)
    }

    @Test func noRunWalkMeansNoPhaseEvents() {
        var engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: [.openEnded(zone: "Z2", label: "Easy")]),
            runWalk: nil
        )
        let events = engine.ingest(LiveMetrics(elapsed: 300, distanceMeters: 900))
        #expect(!events.contains { if case .phaseChanged = $0 { return true }; return false })
        #expect(engine.state.runWalkPhase == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'WorkoutEngine' in scope`.

- [ ] **Step 3: Write WorkoutState**

`FitBud Watch App/Models/WorkoutState.swift`:
```swift
import Foundation

/// Everything the live workout screen renders. Derived entirely from the
/// metric stream — the UI holds no workout logic of its own.
struct WorkoutState: Equatable, Sendable {
    var elapsed: TimeInterval = 0
    var distanceMeters: Double = 0
    var heartRate: Double?
    var activeEnergyKcal: Double = 0

    var currentBlock: TimelineBlock?
    var currentBlockIndex: Int?
    var blockRemaining: TimeInterval?

    var runWalkPhase: RunWalkPhase?
    var phaseRemaining: TimeInterval?

    var splits: [Split] = []
    var isComplete = false

    /// Average pace across the whole workout so far, seconds per kilometre.
    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return elapsed / (distanceMeters / 1000)
    }

    var distanceKm: Double { distanceMeters / 1000 }
}
```

- [ ] **Step 4: Write WorkoutEngine**

`FitBud Watch App/Engine/WorkoutEngine.swift`:
```swift
import Foundation

enum WorkoutEvent: Equatable, Sendable {
    case splitCompleted(Split)
    case phaseChanged(RunWalkPhase)
    case blockChanged(index: Int, block: TimelineBlock)
    /// A fixed-length session has run past its final block.
    case finished
}

/// Turns a stream of sensor snapshots into workout state and discrete events.
///
/// Pure and deterministic: the same sequence of `LiveMetrics` always yields the
/// same events, which is what makes it testable without a watch on a wrist.
struct WorkoutEngine {
    private let timeline: SegmentTimeline
    private let runWalk: RunWalkCycler?

    private var splitDetector = SplitDetector()
    private var lastPhase: RunWalkPhase?
    private var lastBlockIndex: Int?
    private var hasFinished = false

    private(set) var state = WorkoutState()

    init(timeline: SegmentTimeline, runWalk: RunWalkCycler?) {
        self.timeline = timeline
        self.runWalk = runWalk
    }

    /// Feeds one sensor snapshot in and returns everything that changed because
    /// of it. Order is stable: splits, then phase change, then block change,
    /// then completion.
    mutating func ingest(_ metrics: LiveMetrics) -> [WorkoutEvent] {
        state.elapsed = metrics.elapsed
        state.distanceMeters = metrics.distanceMeters
        state.heartRate = metrics.heartRate
        state.activeEnergyKcal = metrics.activeEnergyKcal

        var events: [WorkoutEvent] = []

        let splits = splitDetector.update(
            distanceMeters: metrics.distanceMeters,
            elapsed: metrics.elapsed,
            heartRate: metrics.heartRate
        )
        state.splits = splitDetector.splits
        events.append(contentsOf: splits.map(WorkoutEvent.splitCompleted))

        if let runWalk {
            let phase = runWalk.phase(at: metrics.elapsed)
            state.runWalkPhase = phase
            state.phaseRemaining = runWalk.remainingInPhase(at: metrics.elapsed)
            if phase != lastPhase {
                if lastPhase != nil { events.append(.phaseChanged(phase)) }
                lastPhase = phase
            }
        }

        if let position = timeline.position(at: metrics.elapsed) {
            state.currentBlock = position.block
            state.currentBlockIndex = position.index
            state.blockRemaining = position.remaining
            if position.index != lastBlockIndex {
                events.append(.blockChanged(index: position.index, block: position.block))
                lastBlockIndex = position.index
            }
        } else if !hasFinished {
            // A fixed-length session ran past its final block.
            hasFinished = true
            state.isComplete = true
            state.currentBlock = nil
            state.currentBlockIndex = nil
            state.blockRemaining = nil
            events.append(.finished)
        }

        return events
    }
}
```

Note the phase-change rule: the very first `ingest` sets `lastPhase` without emitting `.phaseChanged`, because starting a run is not a transition. Block changes *do* announce the opening block, so the UI has something to show immediately.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 35 tests.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/Engine/WorkoutEngine.swift" "FitBud Watch App/Models/WorkoutState.swift" "FitBud Watch AppTests/WorkoutEngineTests.swift"
git commit -m "feat: add WorkoutEngine composing splits, run/walk and segments"
```

---

### Task 7: HealthKit capability — entitlement and usage descriptions

**Files:**
- Create: `FitBud Watch App/FitBud Watch App.entitlements`
- Modify: `FitBud.xcodeproj/project.pbxproj` (build settings only)

**Interfaces:**
- Consumes: nothing
- Produces: an app that can legally request HealthKit access

This is the **only** task that edits `project.pbxproj`. Without the entitlement, `HKHealthStore.requestAuthorization` fails at runtime; without the usage strings, the app crashes the moment it asks.

- [ ] **Step 1: Create the entitlements file**

`FitBud Watch App/FitBud Watch App.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.healthkit</key>
	<true/>
	<key>com.apple.developer.healthkit.access</key>
	<array/>
</dict>
</plist>
```

- [ ] **Step 2: Add the build settings**

Run this script — it inserts the settings into both build configurations of the `FitBud Watch App` target only:

```bash
python3 - <<'PY'
import re
path = "FitBud.xcodeproj/project.pbxproj"
src = open(path).read()

additions = '''				CODE_SIGN_ENTITLEMENTS = "FitBud Watch App/FitBud Watch App.entitlements";
				INFOPLIST_KEY_NSHealthShareUsageDescription = "FitBud reads your heart rate, workouts and recovery data to coach your training.";
				INFOPLIST_KEY_NSHealthUpdateUsageDescription = "FitBud saves your runs to Apple Health.";
				INFOPLIST_KEY_WKBackgroundModes = "workout-processing";
'''

# The watch app target's two config blocks are the only ones carrying WKWatchOnly.
anchor = "\t\t\t\tINFOPLIST_KEY_WKWatchOnly = YES;\n"
count = src.count(anchor)
assert count == 2, f"expected 2 watch-app config blocks, found {count}"
assert "CODE_SIGN_ENTITLEMENTS" not in src, "entitlements already configured"

src = src.replace(anchor, anchor + additions)
open(path, "w").write(src)
print("patched", count, "configurations")
PY
```

- [ ] **Step 3: Verify the project still builds and the plist keys landed**

Run:
```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" build 2>&1 | grep -E "error:|\*\* BUILD"
```
Expected: `** BUILD SUCCEEDED **`

Then confirm the generated Info.plist contains the usage strings:
```bash
plutil -p ~/Library/Developer/Xcode/DerivedData/FitBud-*/Build/Products/Debug-watchsimulator/"FitBud Watch App.app"/Info.plist | grep -E "NSHealth|WKBackgroundModes"
```
Expected: both `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` present.

- [ ] **Step 4: Run the test suite to confirm nothing regressed**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 35 tests.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/FitBud Watch App.entitlements" FitBud.xcodeproj/project.pbxproj
git commit -m "build: add HealthKit entitlement and usage descriptions"
```

---

### Task 8: HealthAuthorization

**Files:**
- Create: `FitBud Watch App/Health/HealthAuthorization.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `HealthAuthorization()`, `static var isAvailable: Bool`, `func requestPermissions() async throws`, `enum HealthAuthorizationError { unavailable }`, `static let readTypes: Set<HKObjectType>`, `static let shareTypes: Set<HKSampleType>`

No unit test: this type is a thin wrapper over a system call that cannot run meaningfully in a test bundle. It is exercised manually in Task 12. Keeping it this thin is what makes that acceptable.

- [ ] **Step 1: Write the implementation**

`FitBud Watch App/Health/HealthAuthorization.swift`:
```swift
import Foundation
import HealthKit

enum HealthAuthorizationError: Error {
    case unavailable
}

/// Requests the HealthKit permissions FitBud needs.
///
/// Read types cover both live workout metrics and the recovery signals the
/// history probe (and, from Stage 4, the coach) depends on.
struct HealthAuthorization {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.vo2Max),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType()
    ]

    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.heartRate),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.activeEnergyBurned),
        HKObjectType.workoutType()
    ]

    func requestPermissions() async throws {
        guard Self.isAvailable else { throw HealthAuthorizationError.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }
}
```

- [ ] **Step 2: Verify it compiles and tests still pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 35 tests, no compile errors.

- [ ] **Step 3: Commit**

```bash
git add "FitBud Watch App/Health/HealthAuthorization.swift"
git commit -m "feat: add HealthKit authorization"
```

---

### Task 9: WorkoutRecording protocol and HealthKit recorder

**Files:**
- Create: `FitBud Watch App/Models/WorkoutConfiguration.swift`
- Create: `FitBud Watch App/Models/CompletedWorkout.swift`
- Create: `FitBud Watch App/Health/WorkoutRecording.swift`
- Create: `FitBud Watch App/Health/HealthKitWorkoutRecorder.swift`

**Interfaces:**
- Consumes: `LiveMetrics`, `WorkoutSegment`, `RunWalkCycler`, `Split`
- Produces: `WorkoutConfiguration(title:segments:runWalk:)`, `CompletedWorkout(start:end:distanceMeters:activeEnergyKcal:averageHeartRate:splits:)`, `protocol WorkoutRecording`, `HealthKitWorkoutRecorder()`

**Spec note:** §5.1 defines `start(_ day: PlanDay)`. `PlanDay` does not exist until Stage 2, so Stage 1 uses `WorkoutConfiguration`. Stage 2 adds a `PlanDay -> WorkoutConfiguration` mapping rather than changing this protocol — the seam is deliberate.

- [ ] **Step 1: Write the supporting types**

`FitBud Watch App/Models/WorkoutConfiguration.swift`:
```swift
import Foundation

/// What to record. Stage 2 will map a `PlanDay` onto this.
struct WorkoutConfiguration: Equatable, Sendable {
    let title: String
    let segments: [WorkoutSegment]
    let runWalk: RunWalkCycler?

    /// An unstructured easy run — the default when no plan is loaded.
    static let openEasyRun = WorkoutConfiguration(
        title: "Easy run",
        segments: [.openEnded(zone: "Z2", label: "Easy")],
        runWalk: nil
    )

    /// A long run with 4:1 run/walk, the plan's staple through week 4.
    static let longRun4to1 = WorkoutConfiguration(
        title: "Long run 4:1",
        segments: [.openEnded(zone: "Z2", label: "Long run")],
        runWalk: RunWalkCycler(runSeconds: 240, walkSeconds: 60)
    )

    /// A long run with 5:1 run/walk, used from week 5 and on race day.
    static let longRun5to1 = WorkoutConfiguration(
        title: "Long run 5:1",
        segments: [.openEnded(zone: "Z2", label: "Long run")],
        runWalk: RunWalkCycler(runSeconds: 300, walkSeconds: 60)
    )
}
```

`FitBud Watch App/Models/CompletedWorkout.swift`:
```swift
import Foundation

/// The result of a finished workout, after it has been saved to HealthKit.
struct CompletedWorkout: Equatable, Sendable {
    let start: Date
    let end: Date
    let distanceMeters: Double
    let activeEnergyKcal: Double
    let averageHeartRate: Double?
    let splits: [Split]

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var averagePaceSecPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }
}
```

- [ ] **Step 2: Write the protocol**

`FitBud Watch App/Health/WorkoutRecording.swift`:
```swift
import Foundation

enum WorkoutRecordingError: Error {
    case healthDataUnavailable
    case notRunning
    case sessionFailed(Error)
}

/// The seam between the workout engine and HealthKit.
///
/// Everything above this protocol is pure and testable; everything below it
/// talks to `HKWorkoutSession`. Stage 2 onwards depends on this type, never on
/// the HealthKit implementation directly.
///
/// `@MainActor` because `HKWorkoutSession` and its live builder are main-actor
/// bound, and because the UI observes the resulting state directly. Without the
/// annotation the `@MainActor` implementation cannot satisfy the protocol.
@MainActor
protocol WorkoutRecording: AnyObject {
    /// Emits a snapshot each time HealthKit delivers new sensor data.
    /// Finishes when the workout ends.
    var metrics: AsyncStream<LiveMetrics> { get }

    func start(_ configuration: WorkoutConfiguration) async throws
    func pause() async throws
    func resume() async throws
    func end(splits: [Split]) async throws -> CompletedWorkout
}
```

- [ ] **Step 3: Write the HealthKit implementation**

`FitBud Watch App/Health/HealthKitWorkoutRecorder.swift`:
```swift
import Foundation
import HealthKit

/// Records an outdoor run using `HKWorkoutSession` and `HKLiveWorkoutBuilder`.
///
/// The session is what keeps the app alive and collecting while the wrist is
/// down, so it must be started even for an unstructured run.
@MainActor
final class HealthKitWorkoutRecorder: NSObject, WorkoutRecording {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var continuation: AsyncStream<LiveMetrics>.Continuation?

    private var latestDistance: Double = 0
    private var latestEnergy: Double = 0
    private var latestHeartRate: Double?
    private var heartRateSum: Double = 0
    private var heartRateCount: Int = 0

    let metrics: AsyncStream<LiveMetrics>

    override init() {
        var capturedContinuation: AsyncStream<LiveMetrics>.Continuation!
        metrics = AsyncStream { capturedContinuation = $0 }
        super.init()
        continuation = capturedContinuation
    }

    func start(_ configuration: WorkoutConfiguration) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutRecordingError.healthDataUnavailable
        }

        let hkConfiguration = HKWorkoutConfiguration()
        hkConfiguration.activityType = .running
        hkConfiguration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: hkConfiguration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store,
                workoutConfiguration: hkConfiguration
            )
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            self.startDate = start
            emit(at: start)
        } catch {
            throw WorkoutRecordingError.sessionFailed(error)
        }
    }

    func pause() async throws {
        guard let session else { throw WorkoutRecordingError.notRunning }
        session.pause()
    }

    func resume() async throws {
        guard let session else { throw WorkoutRecordingError.notRunning }
        session.resume()
    }

    func end(splits: [Split]) async throws -> CompletedWorkout {
        guard let session, let builder, let startDate else {
            throw WorkoutRecordingError.notRunning
        }

        let end = Date()
        session.end()
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
        continuation?.finish()

        self.session = nil
        self.builder = nil

        return CompletedWorkout(
            start: startDate,
            end: end,
            distanceMeters: latestDistance,
            activeEnergyKcal: latestEnergy,
            averageHeartRate: heartRateCount > 0 ? heartRateSum / Double(heartRateCount) : nil,
            splits: splits
        )
    }

    private func emit(at date: Date) {
        guard let startDate else { return }
        continuation?.yield(
            LiveMetrics(
                elapsed: date.timeIntervalSince(startDate),
                distanceMeters: latestDistance,
                heartRate: latestHeartRate,
                activeEnergyKcal: latestEnergy
            )
        )
    }
}

extension HealthKitWorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.continuation?.finish() }
    }
}

extension HealthKitWorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType,
                      let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

                switch quantityType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    if let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) {
                        self.latestHeartRate = value
                        self.heartRateSum += value
                        self.heartRateCount += 1
                    }
                case HKQuantityType(.distanceWalkingRunning):
                    if let value = statistics.sumQuantity()?.doubleValue(for: .meter()) {
                        self.latestDistance = value
                    }
                case HKQuantityType(.activeEnergyBurned):
                    if let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        self.latestEnergy = value
                    }
                default:
                    continue
                }
            }
            self.emit(at: Date())
        }
    }
}
```

- [ ] **Step 4: Verify it compiles and tests still pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 35 tests, no compile errors.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/WorkoutConfiguration.swift" "FitBud Watch App/Models/CompletedWorkout.swift" "FitBud Watch App/Health/WorkoutRecording.swift" "FitBud Watch App/Health/HealthKitWorkoutRecorder.swift"
git commit -m "feat: add WorkoutRecording protocol and HealthKit recorder"
```

---

### Task 10: Haptics

**Files:**
- Create: `FitBud Watch App/Support/HapticPlaying.swift`

**Interfaces:**
- Consumes: `WorkoutEvent`, `RunWalkPhase`
- Produces: `protocol HapticPlaying { func play(_ haptic: WorkoutHaptic) }`, `enum WorkoutHaptic { splitCompleted, startRunning, startWalking, workoutComplete }`, `WatchHaptics()`, `func haptic(for:) -> WorkoutHaptic?`

The mapping from event to haptic is pure and worth a test; playing it is a one-line system call that is not.

- [ ] **Step 1: Write the failing test**

`FitBud Watch AppTests/WorkoutEngineTests.swift` — append:
```swift
struct WorkoutHapticMappingTests {
    @Test func splitPlaysTheSplitHaptic() {
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 540, duration: 540, averageHeartRate: nil)
        #expect(haptic(for: .splitCompleted(split)) == .splitCompleted)
    }

    @Test func phaseChangesPlayDistinctHaptics() {
        #expect(haptic(for: .phaseChanged(.walk)) == .startWalking)
        #expect(haptic(for: .phaseChanged(.run)) == .startRunning)
    }

    @Test func finishingPlaysTheCompletionHaptic() {
        #expect(haptic(for: .finished) == .workoutComplete)
    }

    @Test func blockChangesAreSilent() {
        let block = TimelineBlock(kind: .work, duration: 180, zone: "Z4", label: "Threshold")
        #expect(haptic(for: .blockChanged(index: 1, block: block)) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "error:|✘|\*\* TEST"`
Expected: FAIL — `cannot find 'haptic' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Support/HapticPlaying.swift`:
```swift
import Foundation
import WatchKit

enum WorkoutHaptic: Equatable, Sendable {
    case splitCompleted
    case startRunning
    case startWalking
    case workoutComplete
}

/// Which haptic, if any, an event deserves. Block changes are silent because a
/// structured session would otherwise buzz constantly during intervals.
func haptic(for event: WorkoutEvent) -> WorkoutHaptic? {
    switch event {
    case .splitCompleted:
        return .splitCompleted
    case let .phaseChanged(phase):
        return phase == .run ? .startRunning : .startWalking
    case .blockChanged:
        return nil
    case .finished:
        return .workoutComplete
    }
}

protocol HapticPlaying {
    func play(_ haptic: WorkoutHaptic)
}

struct WatchHaptics: HapticPlaying {
    func play(_ haptic: WorkoutHaptic) {
        let type: WKHapticType = switch haptic {
        case .splitCompleted: .notification
        case .startRunning: .start
        case .startWalking: .stop
        case .workoutComplete: .success
        }
        WKInterfaceDevice.current().play(type)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 39 tests.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Support/HapticPlaying.swift" "FitBud Watch AppTests/WorkoutEngineTests.swift"
git commit -m "feat: map workout events to haptics"
```

---

### Task 11: HealthHistoryProbe — resolving spec §12.1

**Files:**
- Create: `FitBud Watch App/Health/HealthHistoryProbe.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `HealthHistoryProbe()`, `struct ProbeResult { metric, oldestSample, sampleCount, spanDays }`, `func probe() async -> [ProbeResult]`

This is the spike that answers the spec's only open architectural question: how far back the watch's local HealthKit store actually goes. If the answer is "not far", `ReadinessMonitor` in Stage 4 must build its own rolling baselines instead of querying history.

- [ ] **Step 1: Write the implementation**

`FitBud Watch App/Health/HealthHistoryProbe.swift`:
```swift
import Foundation
import HealthKit

/// Answers spec §12.1: how deep is the watch's local HealthKit store?
///
/// For each metric the coach depends on, finds the oldest available sample and
/// counts how many exist. Run once on a real device — the simulator has no
/// health data and will report every metric as empty.
struct HealthHistoryProbe {
    struct ProbeResult: Identifiable, Equatable {
        var id: String { metric }
        let metric: String
        let oldestSample: Date?
        let newestSample: Date?
        let sampleCount: Int

        var spanDays: Int? {
            guard let oldestSample, let newestSample else { return nil }
            return Calendar.current.dateComponents([.day], from: oldestSample, to: newestSample).day
        }
    }

    private let store = HKHealthStore()

    private var probedTypes: [(String, HKSampleType)] {
        [
            ("Resting HR", HKQuantityType(.restingHeartRate)),
            ("HRV (SDNN)", HKQuantityType(.heartRateVariabilitySDNN)),
            ("VO2 max", HKQuantityType(.vo2Max)),
            ("Sleep", HKCategoryType(.sleepAnalysis)),
            ("Workouts", HKObjectType.workoutType())
        ]
    }

    func probe() async -> [ProbeResult] {
        var results: [ProbeResult] = []
        for (name, type) in probedTypes {
            results.append(await probe(name: name, type: type))
        }
        return results
    }

    private func probe(name: String, type: HKSampleType) async -> ProbeResult {
        let samples = await fetchAll(type: type)
        let dates = samples.map(\.startDate).sorted()
        return ProbeResult(
            metric: name,
            oldestSample: dates.first,
            newestSample: dates.last,
            sampleCount: samples.count
        )
    }

    private func fetchAll(type: HKSampleType) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles and tests still pass**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 39 tests.

- [ ] **Step 3: Commit**

```bash
git add "FitBud Watch App/Health/HealthHistoryProbe.swift"
git commit -m "feat: add HealthKit history probe for spec 12.1"
```

---

### Task 12: UI and wiring

**Files:**
- Create: `FitBud Watch App/UI/RootView.swift`
- Create: `FitBud Watch App/UI/StartView.swift`
- Create: `FitBud Watch App/UI/LiveWorkoutView.swift`
- Create: `FitBud Watch App/UI/SummaryView.swift`
- Create: `FitBud Watch App/UI/HistoryProbeView.swift`
- Create: `FitBud Watch App/UI/WorkoutSessionModel.swift`
- Modify: `FitBud Watch App/FitBudApp.swift`
- Delete: `FitBud Watch App/ContentView.swift`

**Interfaces:**
- Consumes: everything above
- Produces: a runnable app

- [ ] **Step 1: Write the observable session model**

`FitBud Watch App/UI/WorkoutSessionModel.swift`:
```swift
import Foundation
import Observation

/// Bridges the pure engine to SwiftUI: owns the recorder, pumps its metric
/// stream through the engine, and plays haptics for the events that come out.
@MainActor
@Observable
final class WorkoutSessionModel {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished(CompletedWorkout)
    }

    private(set) var phase: Phase = .idle
    private(set) var state = WorkoutState()
    private(set) var errorMessage: String?

    private let recorder: WorkoutRecording
    private let haptics: HapticPlaying
    private var engine: WorkoutEngine?
    private var pumpTask: Task<Void, Never>?

    init(recorder: WorkoutRecording = HealthKitWorkoutRecorder(), haptics: HapticPlaying = WatchHaptics()) {
        self.recorder = recorder
        self.haptics = haptics
    }

    func start(_ configuration: WorkoutConfiguration) async {
        engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: configuration.segments),
            runWalk: configuration.runWalk
        )
        do {
            try await recorder.start(configuration)
            phase = .running
            pump()
        } catch {
            errorMessage = "Couldn't start: \(error.localizedDescription)"
        }
    }

    private func pump() {
        // This `Task` inherits `@MainActor` from the enclosing type, so the
        // property accesses below need no `await` and no extra hopping.
        pumpTask = Task { [weak self] in
            guard let self else { return }
            for await metrics in self.recorder.metrics {
                guard var engine = self.engine else { continue }
                let events = engine.ingest(metrics)
                self.apply(engine: engine, events: events)
            }
        }
    }

    private func apply(engine: WorkoutEngine, events: [WorkoutEvent]) {
        self.engine = engine
        state = engine.state
        for event in events {
            if let haptic = haptic(for: event) { haptics.play(haptic) }
        }
    }

    func pause() async {
        try? await recorder.pause()
        phase = .paused
    }

    func resume() async {
        try? await recorder.resume()
        phase = .running
    }

    func end() async {
        pumpTask?.cancel()
        do {
            let workout = try await recorder.end(splits: state.splits)
            phase = .finished(workout)
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 2: Write the views**

`FitBud Watch App/UI/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @State private var model = WorkoutSessionModel()

    var body: some View {
        NavigationStack {
            switch model.phase {
            case .idle:
                StartView(model: model)
            case .running, .paused:
                LiveWorkoutView(model: model)
            case let .finished(workout):
                SummaryView(workout: workout)
            }
        }
    }
}
```

`FitBud Watch App/UI/StartView.swift`:
```swift
import SwiftUI

struct StartView: View {
    let model: WorkoutSessionModel
    @State private var authorization = HealthAuthorization()
    @State private var didRequestAccess = false

    private let options: [WorkoutConfiguration] = [
        .openEasyRun, .longRun4to1, .longRun5to1
    ]

    var body: some View {
        List {
            ForEach(options, id: \.title) { option in
                Button(option.title) {
                    Task { await model.start(option) }
                }
            }
            NavigationLink("Health history probe") {
                HistoryProbeView()
            }
            if let errorMessage = model.errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("FitBud")
        .task {
            guard !didRequestAccess else { return }
            didRequestAccess = true
            try? await authorization.requestPermissions()
        }
    }
}
```

`FitBud Watch App/UI/LiveWorkoutView.swift`:
```swift
import SwiftUI

struct LiveWorkoutView: View {
    let model: WorkoutSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(format(elapsed: model.state.elapsed))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()

            HStack {
                Text(String(format: "%.2f km", model.state.distanceKm))
                Spacer()
                Text(model.state.heartRate.map { "\(Int($0)) bpm" } ?? "-- bpm")
            }
            .font(.system(size: 16, weight: .medium))

            Text(paceText)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            if let phase = model.state.runWalkPhase, let remaining = model.state.phaseRemaining {
                Text("\(phase == .run ? "RUN" : "WALK") \(Int(remaining))s")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(phase == .run ? .green : .orange)
            }

            if let block = model.state.currentBlock, block.kind != .open {
                Text(block.label).font(.footnote).foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button(model.phase == .paused ? "Resume" : "Pause") {
                    Task {
                        model.phase == .paused ? await model.resume() : await model.pause()
                    }
                }
                Button("End") { Task { await model.end() } }
                    .tint(.red)
            }
            .font(.footnote)
        }
        .padding(.horizontal, 8)
        .navigationBarBackButtonHidden(true)
    }

    private var paceText: String {
        guard let pace = model.state.averagePaceSecPerKm else { return "--:--/km" }
        return "\(format(elapsed: pace))/km"
    }

    private func format(elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
```

`FitBud Watch App/UI/SummaryView.swift`:
```swift
import SwiftUI

struct SummaryView: View {
    let workout: CompletedWorkout

    var body: some View {
        List {
            row("Distance", String(format: "%.2f km", workout.distanceMeters / 1000))
            row("Time", format(workout.duration))
            row("Avg pace", workout.averagePaceSecPerKm.map { "\(format($0))/km" } ?? "--")
            row("Avg HR", workout.averageHeartRate.map { "\(Int($0)) bpm" } ?? "--")
            row("Energy", "\(Int(workout.activeEnergyKcal)) kcal")

            if !workout.splits.isEmpty {
                Section("Splits") {
                    ForEach(workout.splits, id: \.index) { split in
                        row("km \(split.index)", format(split.paceSecPerKm))
                    }
                }
            }
        }
        .navigationTitle("Done")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.footnote)
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

`FitBud Watch App/UI/HistoryProbeView.swift`:
```swift
import SwiftUI

struct HistoryProbeView: View {
    @State private var results: [HealthHistoryProbe.ProbeResult] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Text("Probing…").foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.metric).font(.footnote).bold()
                    Text("\(result.sampleCount) samples")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let oldest = result.oldestSample {
                        Text("from \(oldest.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let days = result.spanDays {
                        Text("\(days) day span").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("History")
        .task {
            results = await HealthHistoryProbe().probe()
            isLoading = false
        }
    }
}
```

- [ ] **Step 3: Point the app at RootView and delete the template view**

`FitBud Watch App/FitBudApp.swift` — replace `ContentView()` with `RootView()`:
```swift
import SwiftUI

@main
struct FitBud_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

Then: `rm "FitBud Watch App/ContentView.swift"`

- [ ] **Step 4: Build and run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — all 39 tests.

- [ ] **Step 5: Launch on the simulator and look at it**

```bash
xcrun simctl boot BF994011-AC8D-4857-BEFF-F2AD01567CAA 2>/dev/null
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=BF994011-AC8D-4857-BEFF-F2AD01567CAA" -derivedDataPath build build
xcrun simctl install BF994011-AC8D-4857-BEFF-F2AD01567CAA "build/Build/Products/Debug-watchsimulator/FitBud Watch App.app"
xcrun simctl launch BF994011-AC8D-4857-BEFF-F2AD01567CAA mj.FitBud.watchkitapp
sleep 3
xcrun simctl io BF994011-AC8D-4857-BEFF-F2AD01567CAA screenshot /tmp/fitbud-start.png
```

**Read the screenshot.** Expected: a list showing "Easy run", "Long run 4:1", "Long run 5:1", "Health history probe". A blank screen means the app failed to launch — check the launch output before continuing.

The simulator has no heart-rate or GPS data, so a started workout will show zeros. That is expected and is not a failure: the simulator proves the UI renders and the session starts; only a real watch proves the metrics flow.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/UI" "FitBud Watch App/FitBudApp.swift"
git rm "FitBud Watch App/ContentView.swift"
git commit -m "feat: add workout UI and wire up the app"
```

---

## Definition of done

- [ ] `xcodebuild ... test` reports `** TEST SUCCEEDED **` with 39 tests
- [ ] The app launches on the simulator and shows the start list
- [ ] Installed on the real Apple Watch, a run records heart rate, distance, pace and splits
- [ ] Splits buzz at each kilometre; run/walk transitions buzz at 4:00 and 5:00
- [ ] The finished workout appears in the Apple Fitness app
- [ ] The history probe has been run once on the device and its output recorded in spec §12.1

## What Stage 1 deliberately does not do

No AI, no networking, no plan-JSON loading, no readiness gates, no cue rules. The
`WorkoutConfiguration` presets are hardcoded stand-ins for what Stage 2 will read from
`Plan/half-2026-09-27.json`. Resisting the urge to load the plan here is what keeps Stage 1
shippable inside a week.
