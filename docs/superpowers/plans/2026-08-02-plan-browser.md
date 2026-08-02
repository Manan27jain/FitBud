# Training Plan Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the athlete browse the whole nine-week training block — week list → days → day detail — instead of only seeing today's session.

**Architecture:** Read-only throughout. Decode the `rules` block the plan JSON already carries, add pure per-week and per-day completion helpers beside the existing `blockProgress`, route every view through a new `PlanStore.effectivePlan()` seam so Plan B can apply adaptations without touching any view, and build three navigation levels using the existing `NavigationStack`-per-phase structure.

**Tech Stack:** watchOS 11.2 SwiftUI, Swift 5, Swift Testing (`@Test`/`#expect`), HealthKit read-only.

**Spec:** `docs/superpowers/specs/2026-08-02-plan-view-and-adaptation-design.md` — this plan implements §12 "Plan A — the browser" only. Adaptation (projection, divergence, validator, overlay persistence, `adapt()`, proposal UI) is Plan B and is **out of scope here**.

## Global Constraints

- `Models/` and `Engine/` import **Foundation only, never SwiftUI**. Zone colours live in `UI/Theme.swift` as an `HRZone` extension.
- **Never modify** `FitBud Watch App/Health/HealthKitWorkoutRecorder.swift` or `FitBud Watch App/Health/WorkoutRecording.swift`.
- **Never edit** `FitBud.xcodeproj/project.pbxproj`. New `.swift` files are picked up automatically by the Xcode 16 synchronized folder group (`objectVersion = 77`). `xcodebuild` cosmetically re-sorts the file — revert with `git checkout -- FitBud.xcodeproj/project.pbxproj`, never commit it.
- **Swift Testing only** (`import Testing`, `@Test`, `#expect`). Never XCTest. Test target imports `@testable import FitBud_Watch_App`.
- Wrapping `Text` must carry `.fixedSize(horizontal: false, vertical: true)`. Text truncation on small watch faces has been a repeat defect in this project.
- Build/test command:
  ```bash
  xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
    -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 \
    | grep -E "✔|✘|error:|\*\* TEST"
  ```
- Suite is at **193 tests, all passing**. Report the expected count after each task.
- Simulator `ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5` is an Apple Watch Series 10 46mm. Screenshot with `xcrun simctl io <id> screenshot <path>.png`.

## File Structure

| File | Responsibility |
|---|---|
| `Models/PlanRules.swift` | **Create.** `PlanRules`, `ProgressionCaps` — decodes the `rules` block |
| `Models/TrainingPlan.swift` | **Modify.** Add `rules` property, add `startDate` |
| `Models/BlockProgress.swift` | **Modify.** Add `WeekCompletion`, `weekCompletion`, `runs(in:from:)`, `run(on:from:)`; refactor `blockProgress` onto them |
| `Models/PlanStore.swift` | **Modify.** Add `effectivePlan()` seam |
| `UI/Theme.swift` | **Modify.** Add shared `ProgressTrack` view |
| `UI/PlanWeekListView.swift` | **Create.** Nine week rows with completion |
| `UI/PlanWeekDetailView.swift` | **Create.** One week's seven days |
| `UI/PlanDayDetailView.swift` | **Create.** Notes, segments, Start |
| `UI/HomeModel.swift` | **Modify.** Widen the history window to the block |
| `UI/HomeView.swift` | **Modify.** Add Training plan link, rename All sessions → Quick start, use `ProgressTrack` |

---

### Task 1: Decode the plan's rules block

`TrainingPlan` currently decodes `planId`, `goal` and `weeks` only. The JSON's `rules` object — progression caps, immutable rules, zone discipline — is invisible to Swift. Plan B's validator needs the caps; this task makes them readable.

**Files:**
- Create: `FitBud Watch App/Models/PlanRules.swift`
- Modify: `FitBud Watch App/Models/TrainingPlan.swift:99-111`
- Test: `FitBud Watch AppTests/TrainingPlanTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `TrainingPlan.rules: PlanRules`; `PlanRules.progressionCaps: ProgressionCaps` with `weeklyKmIncreaseMax: Double` and `longRunIncreaseMaxKm: Double`; `PlanRules.immutable: [String]`; `PlanRules.zoneDiscipline: String`.

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/TrainingPlanTests.swift`, inside `struct TrainingPlanTests`:

```swift
    @Test func decodesTheProgressionCaps() throws {
        let plan = try loadPlan()
        #expect(plan.rules.progressionCaps.weeklyKmIncreaseMax == 0.2)
        #expect(plan.rules.progressionCaps.longRunIncreaseMaxKm == 2.0)
    }

    @Test func decodesTheImmutableRulesAsProse() throws {
        let plan = try loadPlan()
        // Four rules, kept as text: they are displayed to the athlete and
        // enforced in code, never parsed.
        #expect(plan.rules.immutable.count == 4)
        #expect(plan.rules.immutable.contains { $0.contains("Week 4 cutback") })
        #expect(plan.rules.immutable.contains { $0.contains("Long run never exceeds 16km") })
    }

    @Test func decodesTheZoneDisciplineRule() throws {
        let plan = try loadPlan()
        #expect(plan.rules.zoneDiscipline.contains("80%"))
    }

    @Test func exposesTheBlockStartDate() throws {
        let plan = try loadPlan()
        #expect(TrainingPlan.dayKey(for: try #require(plan.startDate)) == "2026-08-01")
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the build/test command from Global Constraints.
Expected: FAIL — `value of type 'TrainingPlan' has no member 'rules'` and `no member 'startDate'`.

- [ ] **Step 3: Create `PlanRules.swift`**

```swift
import Foundation

/// The plan's own progression limits, read straight from the JSON.
///
/// This is the machine-readable half of the `rules` block: a validator can act
/// on these numbers directly. The `immutable` array beside them is English
/// prose — decoded so the app can quote a rule back to the athlete when a
/// change is refused, but enforced in code rather than parsed.
struct ProgressionCaps: Decodable, Equatable, Sendable {
    /// Maximum weekly volume increase, as a fraction: 0.2 is +20%.
    let weeklyKmIncreaseMax: Double
    /// Maximum long-run increase per step, in kilometres.
    let longRunIncreaseMaxKm: Double
}

/// The `rules` block of the training plan.
///
/// `sleepGate` and `recoveryGate` are present in the JSON and deliberately not
/// decoded: they govern whether *today's* session should be downgraded, which
/// is a separate feature from browsing or reshaping the block. Swift's
/// synthesised decoder ignores keys with no matching property, so they stay
/// available in the file for whenever that feature is built.
struct PlanRules: Decodable, Equatable, Sendable {
    let progressionCaps: ProgressionCaps
    /// Prose, displayed and never parsed. See the type comment above.
    let immutable: [String]
    let zoneDiscipline: String
}
```

- [ ] **Step 4: Add `rules` to `TrainingPlan`**

In `FitBud Watch App/Models/TrainingPlan.swift`, change the stored properties of `TrainingPlan` from:

```swift
    let planId: String
    let goal: Goal
    let weeks: [PlanWeek]
```

to:

```swift
    let planId: String
    let goal: Goal
    /// Decoded as non-optional on purpose: a plan without its rules block is a
    /// plan whose safety limits are unknown, and this project prefers to fail
    /// loudly at decode time over running with silent defaults — the same
    /// choice `PlanSegment` makes for an unknown segment kind.
    let rules: PlanRules
    let weeks: [PlanWeek]
```

- [ ] **Step 5: Add `startDate` to the `TrainingPlan` extension**

In the same file, inside `extension TrainingPlan` (after `daysToRace(from:)`):

```swift
    /// The block's first calendar day, for bounding history queries.
    ///
    /// Builds its own formatter rather than sharing a static one: `DateFormatter`
    /// is a non-`Sendable` class, and the two methods above already take this
    /// approach for the same reason.
    var startDate: Date? {
        guard let first = weeks.first?.start else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: first)
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Expected: PASS. Suite **197 tests** (193 + 4).

- [ ] **Step 7: Commit**

```bash
git add "FitBud Watch App/Models/PlanRules.swift" \
        "FitBud Watch App/Models/TrainingPlan.swift" \
        "FitBud Watch AppTests/TrainingPlanTests.swift"
git commit -m "feat: decode the plan's rules block and block start date"
```

---

### Task 2: Per-week and per-day completion, and the effectivePlan seam

`blockProgress` computes completion for the *current* week only. The browser needs it for all nine, and per-day for the ✓ marks. Extract the shared matching logic rather than duplicating it, and widen the home screen's history window so the data actually covers the block.

**Files:**
- Modify: `FitBud Watch App/Models/BlockProgress.swift`
- Modify: `FitBud Watch App/Models/PlanStore.swift`
- Modify: `FitBud Watch App/UI/HomeModel.swift:44-53`
- Test: `FitBud Watch AppTests/BlockProgressTests.swift`

**Interfaces:**
- Consumes: `TrainingPlan.startDate` (Task 1).
- Produces:
  - `func runs(in week: PlanWeek, from runs: [HistoricRun]) -> [HistoricRun]`
  - `func run(on day: PlanDay, from runs: [HistoricRun]) -> HistoricRun?`
  - `struct WeekCompletion { completedKm, plannedKm: Double; completedSessions, plannedSessions: Int; var volumeFraction: Double }`
  - `func weekCompletion(week: PlanWeek, runs: [HistoricRun]) -> WeekCompletion`
  - `static func PlanStore.effectivePlan(name:) throws -> TrainingPlan`

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/BlockProgressTests.swift`:

```swift
struct WeekCompletionTests {
    private func plan() throws -> TrainingPlan { try PlanStore.loadBundled() }

    private func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return try #require(formatter.date(from: string))
    }

    /// Named `historicRun`, not `run`, on purpose: a member called `run` would
    /// sit beside the global `run(on:from:)` these tests exercise, and leaving
    /// overload resolution to sort that out is a trap for whoever edits next.
    private func historicRun(_ isoDate: String, km: Double, hr: Double? = 155) throws -> HistoricRun {
        HistoricRun(
            id: UUID(),
            date: try date(isoDate),
            distanceMeters: km * 1000,
            duration: km * 540,          // 9:00/km
            averageHeartRate: hr
        )
    }

    @Test func matchesRunsToTheWeekThatContainsThem() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let matched = runs(in: week, from: [
            try historicRun("2026-08-04", km: 4),   // inside week 1
            try historicRun("2026-08-09", km: 8),   // inside week 1 (Sunday)
            try historicRun("2026-08-11", km: 5)    // week 2 — must not match
        ])
        #expect(matched.count == 2)
    }

    @Test func sumsCompletedVolumeAndSessionsForAWeek() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [
            try historicRun("2026-08-04", km: 4),
            try historicRun("2026-08-09", km: 8)
        ])
        #expect(abs(completion.completedKm - 12) < 0.0001)
        #expect(completion.completedSessions == 2)
        #expect(completion.plannedKm == 16)
        // Week 1 runs Tue easy 4km, Thu easy 4km, Sun long 8km.
        #expect(completion.plannedSessions == 3)
    }

    @Test func volumeFractionCapsAtOneOnAnOvershoot() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [try historicRun("2026-08-04", km: 40)])
        #expect(completion.volumeFraction == 1)
    }

    @Test func aWeekWithNoRunsCompletesNothing() throws {
        let plan = try plan()
        let week = try #require(plan.weeks.first { $0.index == 1 })
        let completion = weekCompletion(week: week, runs: [])
        #expect(completion.completedKm == 0)
        #expect(completion.completedSessions == 0)
        #expect(completion.volumeFraction == 0)
    }

    @Test func findsTheRunRecordedOnASpecificDay() throws {
        let plan = try plan()
        let day = try #require(plan.day(on: try date("2026-08-04")))
        let matched = run(on: day, from: [
            try historicRun("2026-08-04", km: 4),
            try historicRun("2026-08-09", km: 8)
        ])
        #expect(abs((matched?.distanceKm ?? 0) - 4) < 0.0001)
    }

    @Test func aDayWithNoRunHasNoMatch() throws {
        let plan = try plan()
        let day = try #require(plan.day(on: try date("2026-08-03")))   // rest day
        #expect(run(on: day, from: [try historicRun("2026-08-04", km: 4)]) == nil)
    }

    @Test func effectivePlanReturnsTheBundledPlanForNow() throws {
        #expect(try PlanStore.effectivePlan().planId == "half-2026-09-27")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `cannot find 'weekCompletion' in scope`, `'runs(in:from:)'`, `'run(on:from:)'`, `type 'PlanStore' has no member 'effectivePlan'`.

- [ ] **Step 3: Add the helpers to `BlockProgress.swift`**

Insert above the existing `blockProgress(plan:runs:asOf:)` function:

```swift
/// The runs that fall inside `week`, matched by calendar day.
///
/// Matching is on the plan's own `yyyy-MM-dd` day strings rather than on `Date`
/// comparison, for the reason `TrainingPlan.dayKey(for:)` documents: a plan day
/// is a calendar day, and comparing `Date`s drags in timezone and DST questions
/// a calendar day does not have.
func runs(in week: PlanWeek, from runs: [HistoricRun]) -> [HistoricRun] {
    let weekDayKeys = Set(week.days.map(\.date))
    return runs.filter { weekDayKeys.contains(TrainingPlan.dayKey(for: $0.date)) }
}

/// The run recorded on `day`, if there is one.
func run(on day: PlanDay, from runs: [HistoricRun]) -> HistoricRun? {
    runs.first { TrainingPlan.dayKey(for: $0.date) == day.date }
}

/// What the athlete actually did in one plan week, against what it asked for.
struct WeekCompletion: Equatable, Sendable {
    let completedKm: Double
    let plannedKm: Double
    let completedSessions: Int
    let plannedSessions: Int

    /// Completed volume as a fraction of planned, capped at 1 so an overshoot
    /// does not draw a bar past its own track.
    var volumeFraction: Double {
        guard plannedKm > 0 else { return 0 }
        return min(completedKm / plannedKm, 1)
    }
}

/// Completion for any week of the block — the plan browser asks this of all
/// nine, where `blockProgress` below asks it of the current one only.
func weekCompletion(week: PlanWeek, runs allRuns: [HistoricRun]) -> WeekCompletion {
    let matched = runs(in: week, from: allRuns)
    return WeekCompletion(
        completedKm: matched.reduce(0) { $0 + $1.distanceKm },
        plannedKm: week.targetKm,
        completedSessions: matched.count,
        plannedSessions: week.days.filter(\.isRunningSession).count
    )
}
```

- [ ] **Step 4: Refactor `blockProgress` onto the new helpers**

Replace the body of `blockProgress(plan:runs:asOf:)` with:

```swift
func blockProgress(plan: TrainingPlan, runs allRuns: [HistoricRun], asOf date: Date) -> BlockProgress? {
    guard let week = plan.week(containing: date) else { return nil }

    let runsThisWeek = runs(in: week, from: allRuns)
    let completion = weekCompletion(week: week, runs: allRuns)

    let easyShare: Double? = runsThisWeek.isEmpty
        ? nil
        : Double(runsThisWeek.filter(\.isEasy).count) / Double(runsThisWeek.count)

    // Week 0 is the two-day calibration bridge, so the block is eight numbered
    // training weeks regardless of how many entries the array holds.
    let totalWeeks = plan.weeks.map(\.index).max() ?? 0

    return BlockProgress(
        daysToRace: plan.daysToRace(from: date),
        weekIndex: week.index,
        totalWeeks: totalWeeks,
        weekFocus: week.focus,
        plannedKm: completion.plannedKm,
        completedKm: completion.completedKm,
        plannedSessions: completion.plannedSessions,
        completedSessions: completion.completedSessions,
        easyShare: easyShare
    )
}
```

Keep the existing doc comment above the function unchanged.

- [ ] **Step 5: Add the `effectivePlan` seam to `PlanStore.swift`**

Replace the `PlanStore` enum's doc comment and add one method:

```swift
/// Loads the training plan.
///
/// `loadBundled` returns the plan exactly as it ships. `effectivePlan` returns
/// the plan as the athlete should see it — today those are the same thing, and
/// every view goes through `effectivePlan` so that when accepted adaptations
/// arrive they apply in one place rather than at every call site.
enum PlanStore {
    static let bundledPlanName = "half-2026-09-27"

    static func loadBundled(name: String = bundledPlanName) throws -> TrainingPlan {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw PlanStoreError.notBundled(name)
        }
        do {
            return try JSONDecoder().decode(TrainingPlan.self, from: Data(contentsOf: url))
        } catch {
            throw PlanStoreError.undecodable(error)
        }
    }

    /// The plan with any accepted adaptations applied. Identical to
    /// `loadBundled` until Plan B introduces the overlay.
    static func effectivePlan(name: String = bundledPlanName) throws -> TrainingPlan {
        try loadBundled(name: name)
    }
}
```

- [ ] **Step 6: Widen the home screen's history window**

In `FitBud Watch App/UI/HomeModel.swift`, change `load(asOf:)` to load through the seam and to query history from the start of the block. Replace lines 35–53 with:

```swift
        let plan: TrainingPlan
        do {
            plan = try PlanStore.effectivePlan()
            self.plan = plan
            today = plan.day(on: date)
        } catch {
            loadError = error.localizedDescription
            return
        }

        // The plan browser shows completion for every week of the block, not
        // just the fortnight the home cards read, so the window is the block
        // itself. Runs before it belong to no plan week and would be filtered
        // out anyway. HealthKit returns these newest-first, so the home
        // screen's `recentRuns.prefix(4)` still shows the most recent four.
        let fallback = Calendar.current.date(byAdding: .day, value: -14, to: date) ?? date
        let since = plan.startDate ?? fallback
        do {
            recentRuns = try await history.recentRuns(since: since)
        } catch {
            // A history read failure must not take the whole screen down: the
            // plan and today's session are still worth showing.
            recentRuns = []
        }

        progress = blockProgress(plan: plan, runs: recentRuns, asOf: date)
```

- [ ] **Step 7: Run tests to verify they pass**

Expected: PASS, including the pre-existing `BlockProgressTests` (the refactor must not change any of their results). Suite **204 tests** (197 + 7).

- [ ] **Step 8: Commit**

```bash
git add "FitBud Watch App/Models/BlockProgress.swift" \
        "FitBud Watch App/Models/PlanStore.swift" \
        "FitBud Watch App/UI/HomeModel.swift" \
        "FitBud Watch AppTests/BlockProgressTests.swift"
git commit -m "feat: per-week and per-day plan completion, effectivePlan seam"
```

---

### Task 3: The day detail, and starting from it

The leaf of the browser, built first so every later view links to something that already exists. Shows the notes and structure the list rows cannot fit, and starts the session.

Starting from three levels deep is safe: `RootView` gives each `model.phase` its own `NavigationStack`, so a phase change to `.running` tears the whole stack down rather than swapping a root beneath pushed views. That was the E7 navigation bug and its fix — do not add a `NavigationPath` or a dismissal here.

**Files:**
- Create: `FitBud Watch App/UI/PlanDayDetailView.swift`

**Interfaces:**
- Consumes: `run(on:from:)` (Task 2); `WorkoutConfiguration(planDay:)` and `model.start(_:)`, both existing; `formatPace(_:)` from `Support/DurationFormatting.swift`.
- Produces: `PlanDayDetailView(day:runs:model:today:)` — navigated to by `PlanWeekDetailView` in Task 4.

- [ ] **Step 1: Create `PlanDayDetailView.swift`**

```swift
import SwiftUI

/// One day of the plan in full: what it asks for, why, and a way to start it.
struct PlanDayDetailView: View {
    let day: PlanDay
    let runs: [HistoricRun]
    let model: WorkoutSessionModel
    let today: Date

    private var completed: HistoricRun? { run(on: day, from: runs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                if let completed { completedCard(completed) }
                if !day.segments.isEmpty { segmentsCard }
                if !day.notes.isEmpty {
                    Text(day.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if day.isRunningSession { startButton }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(day.dow)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.date)
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(day.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = plannedDetail {
                Text(detail)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Target, zone with its real bpm range, and run/walk ratio — the same
    /// grammar the home screen's today card uses, so the two agree.
    private var plannedDetail: String? {
        var parts: [String] = []
        if day.targetKm > 0 { parts.append(String(format: "%.0f km", day.targetKm)) }
        if day.targetMin > 0 { parts.append("\(Int(day.targetMin)) min") }
        if let zone = day.zone, let hrZone = HRZone.table.first(where: { $0.id == zone }) {
            parts.append("\(zone) \(hrZone.lowerBPM)–\(hrZone.upperBPM) bpm")
        }
        if let runWalk = day.runWalk {
            parts.append("run \(Int(runWalk.runMin))′/walk \(Int(runWalk.walkMin))′")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func completedCard(_ completedRun: HistoricRun) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("COMPLETED")
                .font(Theme.captionFont)
                .foregroundStyle(.green)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", completedRun.distanceKm))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("KM")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(completedRun.paceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let heartRate = completedRun.averageHeartRate {
                Text("\(Int(heartRate)) bpm average · \(completedRun.zone?.name ?? "no zone")")
                    .font(.system(size: 10))
                    .foregroundStyle(completedRun.isEasy ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var segmentsCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("STRUCTURE")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            ForEach(Array(day.segments.enumerated()), id: \.offset) { _, segment in
                Text(describe(segment))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func describe(_ segment: PlanSegment) -> String {
        switch segment {
        case let .warmup(minutes, zone, _):
            "Warm up \(Int(minutes)) min · \(zone)"
        case let .cooldown(minutes, zone, _):
            "Cool down \(Int(minutes)) min · \(zone)"
        case let .repeatBlock(times, work, recover):
            "\(times) × \(Int(work.minutes)) min \(work.zone), \(Int(recover.minutes)) min \(recover.zone)"
        }
    }

    /// Any running session can be started, including a future one — the athlete
    /// may legitimately want to run Sunday's long run on Saturday, and the date
    /// is shown right above this button so the choice is informed.
    private var startButton: some View {
        Button {
            Task { await model.start(WorkoutConfiguration(planDay: day)) }
        } label: {
            Label(completed == nil ? "Start" : "Run it again", systemImage: "figure.run")
                .frame(maxWidth: .infinity)
        }
        .tint(HRZone.table.first { $0.id == day.zone }?.color ?? .green)
    }
}
```

Note the parameter of `completedCard` is named `completedRun`, not `run`: a parameter called `run` would shadow the global `run(on:from:)` this file also calls, and leaving that to overload resolution is a trap for whoever edits next.

- [ ] **Step 2: Build**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. This view is not yet reachable from anywhere, which is expected — Task 4 links to it.

- [ ] **Step 3: Run the full suite**

Run the test command from Global Constraints.
Expected: PASS, **204 tests** (no new tests — this view is verified by screenshot in Task 6).

- [ ] **Step 4: Commit**

```bash
git add "FitBud Watch App/UI/PlanDayDetailView.swift"
git commit -m "feat: plan day detail, with structure and a start button"
```

---

### Task 4: The week detail — seven days

**Files:**
- Create: `FitBud Watch App/UI/PlanWeekDetailView.swift`

**Interfaces:**
- Consumes: `run(on:from:)` (Task 2); `PlanDayDetailView(day:runs:model:today:)` (Task 3); `formatPace(_:)` from `Support/DurationFormatting.swift`.
- Produces: `PlanWeekDetailView(week:runs:model:today:)` — navigated to by `PlanWeekListView` in Task 5.

- [ ] **Step 1: Create `PlanWeekDetailView.swift`**

```swift
import SwiftUI

/// One week of the block, day by day.
struct PlanWeekDetailView: View {
    let week: PlanWeek
    let runs: [HistoricRun]
    let model: WorkoutSessionModel
    let today: Date

    private var todayKey: String { TrainingPlan.dayKey(for: today) }

    var body: some View {
        List {
            ForEach(week.days, id: \.date) { day in
                NavigationLink {
                    PlanDayDetailView(day: day, runs: runs, model: model, today: today)
                } label: {
                    row(for: day)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle(week.index == 0 ? "Bridge" : "Week \(week.index)")
    }

    @ViewBuilder private func row(for day: PlanDay) -> some View {
        let completed = run(on: day, from: runs)
        let isToday = day.date == todayKey

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(day.dow.uppercased())
                    .font(Theme.captionFont)
                    .foregroundStyle(isToday ? Color.green : Color.secondary)
                if isToday {
                    Text("TODAY")
                        .font(Theme.captionFont)
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)
                if let completed {
                    // The tick answers "did I do it"; the dot's colour answers
                    // "was it easy", which is the rule the whole plan turns on.
                    Circle()
                        .fill(completed.zone?.color ?? .gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
            }

            Text(day.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(day.isRunningSession ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = detail(for: day) {
                Text(detail)
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The planned shape of the day, or what was actually run once there is a
    /// recording to report instead.
    private func detail(for day: PlanDay) -> String? {
        if let completed = run(on: day, from: runs) {
            let pace = completed.paceSecPerKm.map { " · \(formatPace($0))/km" } ?? ""
            return String(format: "%.1f km", completed.distanceKm) + pace
        }
        var parts: [String] = []
        if day.targetKm > 0 { parts.append(String(format: "%.0f km", day.targetKm)) }
        else if day.targetMin > 0 { parts.append("\(Int(day.targetMin)) min") }
        if let zone = day.zone { parts.append(zone) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run the full suite**

Expected: PASS, **204 tests**.

- [ ] **Step 4: Commit**

```bash
git add "FitBud Watch App/UI/PlanWeekDetailView.swift"
git commit -m "feat: plan week detail, seven days with completion marks"
```

---

### Task 5: The week list

Nine rows, one per week, each showing where the athlete stands in it. This is the browser's entry point and the last of the three views.

`HomeView` has a private `progressBar(fraction:color:)` that this view needs too. Extract it into `Theme.swift` beside `CaptionLabel` rather than writing a second copy.

**Files:**
- Modify: `FitBud Watch App/UI/Theme.swift`
- Modify: `FitBud Watch App/UI/HomeView.swift:261-271` (delete the private bar, use the shared one)
- Create: `FitBud Watch App/UI/PlanWeekListView.swift`

**Interfaces:**
- Consumes: `weekCompletion(week:runs:)` and `WeekCompletion.volumeFraction` (Task 2); `PlanWeekDetailView(week:runs:model:today:)` (Task 4).
- Produces: `ProgressTrack(fraction:color:)`; `PlanWeekListView(plan:runs:model:today:)` — linked from `HomeView` in Task 6.

- [ ] **Step 1: Add `ProgressTrack` to `Theme.swift`**

Append to the end of `FitBud Watch App/UI/Theme.swift`:

```swift
/// The thin capsule bar used wherever the app shows completed-against-planned.
///
/// Lives here beside `CaptionLabel` because it is now used by both the home
/// screen and the plan browser, and two copies of a progress bar drift the way
/// the five live pages' typography drifted before `Theme` existed.
struct ProgressTrack: View {
    let fraction: Double
    var color: Color = .green

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    // A floor of 2pt so a barely-started week still shows a
                    // mark rather than an empty track that reads as "no data".
                    .frame(width: max(2, geometry.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}
```

- [ ] **Step 2: Point `HomeView` at the shared bar**

In `FitBud Watch App/UI/HomeView.swift`, delete the private `progressBar(fraction:color:)` method (lines 261–271) and replace its two call sites:

- In `weekCard`: `progressBar(fraction: progress.volumeFraction, color: .green)` becomes `ProgressTrack(fraction: progress.volumeFraction)`
- In `easyCard`: `progressBar(fraction: easyShare, color: onTarget ? .green : .orange)` becomes `ProgressTrack(fraction: easyShare, color: onTarget ? .green : .orange)`

- [ ] **Step 3: Create `PlanWeekListView.swift`**

```swift
import SwiftUI

/// The whole block, one row per week.
///
/// The home screen can only answer "what am I doing today". This answers "what
/// does the rest of this look like", which is the question an athlete eight
/// weeks out from a race actually asks.
struct PlanWeekListView: View {
    let plan: TrainingPlan
    let runs: [HistoricRun]
    let model: WorkoutSessionModel
    let today: Date

    private var currentWeekIndex: Int? { plan.week(containing: today)?.index }

    var body: some View {
        List {
            ForEach(plan.weeks, id: \.index) { week in
                NavigationLink {
                    PlanWeekDetailView(week: week, runs: runs, model: model, today: today)
                } label: {
                    row(for: week)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Plan")
    }

    @ViewBuilder private func row(for week: PlanWeek) -> some View {
        let completion = weekCompletion(week: week, runs: runs)
        let isCurrent = week.index == currentWeekIndex

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title(for: week))
                    .font(Theme.captionFont)
                    // The only colour on the row, so "where am I" is answerable
                    // without reading a single number.
                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                Spacer(minLength: 0)
                Text(String(format: "%.1f km", week.targetKm))
                    .font(Theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(week.focus)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            // Only weeks with something recorded get a bar. An empty track on
            // all six future weeks would read as "you have failed these".
            if completion.completedSessions > 0 {
                ProgressTrack(fraction: completion.volumeFraction)
                Text(String(
                    format: "%.1f / %.0f km · %d of %d",
                    completion.completedKm, completion.plannedKm,
                    completion.completedSessions, completion.plannedSessions
                ))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Week 0 is the two-day calibration bridge, not a numbered training week —
    /// calling it "Week 0" reads as an off-by-one error.
    private func title(for week: PlanWeek) -> String {
        week.index == 0 ? "BRIDGE" : "WEEK \(week.index)"
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full suite**

Expected: PASS, **204 tests**. The existing suite must still be green after the `HomeView` bar swap.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/UI/Theme.swift" \
        "FitBud Watch App/UI/PlanWeekListView.swift" \
        "FitBud Watch App/UI/HomeView.swift"
git commit -m "feat: plan week list, with a shared progress track"
```

---
### Task 6: Wire it to the home screen and verify end to end

Also fixes a standing misnomer: the home screen's **All sessions** link goes to `SessionListView`, which offers three hardcoded ad-hoc workouts and has nothing to do with the plan. With a real plan browser one tap away, that name is actively wrong.

**Files:**
- Modify: `FitBud Watch App/UI/HomeView.swift:40-48`

**Interfaces:**
- Consumes: `PlanWeekListView(plan:runs:model:today:)` (Task 3), `home.plan`, `home.recentRuns` (existing `HomeModel` properties).
- Produces: nothing downstream — this is the last task of Plan A.

- [ ] **Step 1: Add the Training plan link and rename the ad-hoc one**

In `FitBud Watch App/UI/HomeView.swift`, replace:

```swift
                NavigationLink("All sessions") {
                    SessionListView(model: model)
                }
                .font(.footnote)
```

with:

```swift
                if let plan = home.plan {
                    NavigationLink("Training plan") {
                        PlanWeekListView(
                            plan: plan,
                            runs: home.recentRuns,
                            model: model,
                            today: Date()
                        )
                    }
                    .font(.footnote)
                }

                // Not the plan — three ad-hoc configurations for when the
                // athlete wants something other than what today prescribes.
                // It was called "All sessions", which is what the plan browser
                // above actually is.
                NavigationLink("Quick start") {
                    SessionListView(model: model)
                }
                .font(.footnote)
```

- [ ] **Step 2: Build and install on the simulator**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" \
  -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" \
  -derivedDataPath /tmp/fitbud-dd build 2>&1 | tail -3
xcrun simctl boot ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 2>/dev/null
xcrun simctl install ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 \
  "/tmp/fitbud-dd/Build/Products/Debug-watchsimulator/FitBud Watch App.app"
xcrun simctl launch ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 mj.FitBud.watchkitapp
```

- [ ] **Step 3: Screenshot the four screens**

Drive the simulator by tapping with `osascript` (`tell application "System Events" to tell process "Simulator" to click at {x, y}`) and scrolling with a compiled `CGEvent` scroll helper — the Simulator's native Crown accessibility actions silently do nothing.

Capture and visually inspect each:

1. **Home** — shows **Training plan** above **Quick start**.
2. **Plan** — nine week rows; the current week's title in green; completed weeks showing a bar and a `x.x / yy km · n of m` line; future weeks showing no bar.
3. **Week detail** — seven day rows; today marked; any completed day carrying a zone dot and a green tick with the actual distance and pace.
4. **Day detail** — title, target, zone with bpm range, run/walk ratio, structure lines for a session that has segments (use 2026-08-20, the week 3 tempo, which has warmup + repeat + cooldown), the notes, and the Start button.

```bash
xcrun simctl io ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5 screenshot /tmp/plan-<n>.png
```

**Reject and fix any screenshot showing truncated text** (a trailing `…`). This project has shipped truncation defects three times; `.fixedSize(horizontal: false, vertical: true)` is on every wrapping `Text` in these views and any ellipsis means one was missed or a frame is too narrow.

- [ ] **Step 4: Verify starting from the day detail navigates immediately**

From **Day detail** for a running session, tap **Start**. The Effort page must appear immediately, with no back tap needed. Screenshot it.

This is the E7 regression check: `RootView` gives each phase its own `NavigationStack`, so starting from three levels deep must tear the stack down rather than leave the day detail on screen. If the day detail is still visible after tapping Start, stop and report — do not patch it in the view.

- [ ] **Step 5: Confirm the untouchable files are untouched**

```bash
git diff --stat main -- \
  "FitBud Watch App/Health/HealthKitWorkoutRecorder.swift" \
  "FitBud Watch App/Health/WorkoutRecording.swift"
git status --short FitBud.xcodeproj/project.pbxproj
```
Expected: both empty. If `project.pbxproj` was re-sorted by `xcodebuild`, revert it:
```bash
git checkout -- FitBud.xcodeproj/project.pbxproj
```

- [ ] **Step 6: Run the full suite**

Expected: PASS, **204 tests**.

- [ ] **Step 7: Commit**

```bash
git add "FitBud Watch App/UI/HomeView.swift"
git commit -m "feat: reach the plan browser from home, rename the ad-hoc list"
```

---

## What Plan B adds on top

Recorded here so this plan's reviewers know what is deliberately absent, not forgotten:

`PlanOverlay` persistence, `PlanProjection`, `PlanDivergence`, `MutationValidator`, `AIProviding.adapt()`, `ProposalView`, and the `●  adjusted · was 19` badges on the week rows.

The seam they land in is `PlanStore.effectivePlan()` from Task 2. The spec writes that method as `effectivePlan(overlay:)`; this plan ships it as `effectivePlan(name:)` with no overlay parameter, because `PlanOverlay` does not exist yet and a parameter nothing can supply is a type invented on speculation. Plan B adds the parameter then — and the change is cheap, because **`HomeModel.load(asOf:)` is the only call site in the app**. Every view here receives its `TrainingPlan` as a parameter and never loads one itself, so no view built in this plan needs changing.

---

## Execution record

Executed subagent-driven on branch `feature/plan-browser`, 7 commits, suite 193 → 204.

**One plan defect found in the pre-flight scan and fixed before Task 1.** Tasks 3–5
originally built the three views top-down, so Task 3's commit referenced
`PlanWeekDetailView` before it existed — a commit that cannot compile, followed by a
step demanding "204 tests PASS". The plan also mandated stubbing a `NavigationLink`
destination, building, then restoring it before commit, which leaves the committed tree
broken. Reversed to bottom-up: Task 3 = `PlanDayDetailView` (leaf), Task 4 =
`PlanWeekDetailView`, Task 5 = `PlanWeekListView`. Every commit now compiles alone and
all stubbing steps are gone. No requirement was added, removed, or reinterpreted.

**One item parked.** Tapping Start does not navigate to the Effort page on the
simulator. Ruled pre-existing and environmental, not a regression: `git diff main..HEAD`
is empty for `UI/WorkoutSessionModel.swift`, `Health/` and `UI/RootView.swift`; the same
hang reproduces on Home's own unmodified Start button; the Demo run — same `RootView`
phase-switch teardown, fake recorder — navigates instantly; and `RootView` still gives
each phase its own `NavigationStack`, so the E7 fix is structurally intact. Almost
certainly `HKWorkoutSession`/`beginCollection` hanging on a watchOS simulator with no
paired device. **Still owed a real-device check.**

## Known follow-ups

None block merge; all were triaged as acceptable-to-defer by the final whole-branch
review. Ordered by value.

1. **Three divergent implementations of "describe a planned day"** — the best candidate
   for Plan B's opening work, since Plan B touches these views anyway.
   `HomeView.sessionDetail` omits `targetMin` entirely and returns `""` rather than
   `nil`; `PlanWeekDetailView.detail(for:)` uses `if km / else if min` and a bare zone;
   `PlanDayDetailView.plannedDetail` uses two independent `if`s and renders the zone
   with its bpm range. No day in the current plan sets both `targetKm` and `targetMin`,
   so nothing is dropped today — but Home shows no duration at all for min-only days
   (strength, cross-training, and week 0's 2026-08-01). One
   `PlanDay.plannedSummary(verbosity:)` in `Models/` would collapse all three.
2. **`WorkoutSessionModel:169,374` and `CoachContext:106` still call `loadBundled()`** —
   already recorded in the spec's §12 as a Plan B prerequisite. Harmless while the two
   functions are identical; a real defect the moment they are not.
3. **`PlanWeekListView`'s bar gate** uses `completedSessions > 0`. Gating a *volume* bar
   on `completedKm > 0` is the semantic fix — one word. Reachable today because
   `WorkoutHistoryReading` coerces a missing distance sample to `0`.
4. **`run(on:from:)` uses `.first`** — two runs on one day count as 2 in the week list
   but render one tick and one card.
5. **`WeekCompletion` duplicates four `BlockProgress` fields** and copies
   `volumeFraction` verbatim; `BlockProgress` should compose a `WeekCompletion`.
6. **"RECENT RUNS" on Home** can now surface runs up to nine weeks old, since the
   history window widened from 14 days to the whole block.
7. **Pre-existing, outside this diff:** `HomeView.swift:111`
   `Text(sessionDetail(today))` wraps and lacks `.fixedSize`.
