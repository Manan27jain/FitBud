# AI Coaching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Effort screen a coach's voice — an LLM writes the session's coaching before the run, a pure local engine delivers it with no network on the critical path, and walk breaks get one live call so the coach can react to how the run is actually going.

**Architecture:** All decision logic is pure and Foundation-only: `CueRule` matching, the five rate-limit rules, and context assembly are unit tested without a network, a clock, or HealthKit. `AIProviding` and `CoachSpeaking` are protocol seams with fakes in tests. Nothing the AI does can prevent a run from being recorded.

**Tech Stack:** Swift 5, SwiftUI, Swift Testing, `URLSession`, `AVSpeechSynthesizer`, OpenAI `gpt-5-mini` with `response_format: json_schema`, watchOS 11.2.

## Global Constraints

- Deployment target **watchOS 11.2**, Swift **5.0** language mode.
- Test framework is **Swift Testing** (`import Testing`, `@Test`, `#expect`). Never XCTest.
- Test module: `@testable import FitBud_Watch_App`.
- Build/test command:
  `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test`
  Always pipe through `grep -E "✔|✘|error:|\*\* TEST"` — raw output is enormous.
- Simulator: **Apple Watch Series 10 (46mm)**, UUID `ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5`.
- Xcode 16 **synchronized folder groups** (`objectVersion = 77`): new `.swift` files compile automatically. **Never edit `project.pbxproj`.** `xcodebuild` cosmetically re-sorts it on most runs — revert with `git checkout -- FitBud.xcodeproj/project.pbxproj`, never commit it.
- **Never modify** `Health/HealthKitWorkoutRecorder.swift` or `Health/WorkoutRecording.swift`.
- **`Models/` and `Engine/` import Foundation only, never SwiftUI.** `Coach/` follows the same rule except where noted.
- Suite is **125 tests** at the start of this plan. Each task states its expected total.
- Model id: **`gpt-5-mini`**, a single constant.
- Cue messages: **≤ 12 words**, enforced on decode.
- Rate limits, copied verbatim from spec §4: **90s** between any two cues; urgent bypasses the queue but respects a **45s** floor; non-repeating rules fire once per workout; **at most one cue per walk break**; a stale cue is dropped, not deferred.
- Only `zoneAbove` and `zoneBelow` may be `.immediate`.

## File Structure

```
FitBud Watch App/
  Resources/
    Secrets.plist              NEW, GITIGNORED — the actual key
    Secrets.example.plist      NEW, committed — documents the shape
  Models/
    Cue.swift                  NEW  CueTrigger, CueUrgency, CueRule, Cue, SessionBrief, WorkoutAnalysis
    DefaultCueBundle.swift     NEW  The offline fallback, built from the plan day's zone
    CoachContext.swift         NEW  CoachContext, LiveCoachContext — what the model is told
  Engine/
    CoachEngine.swift          NEW  Trigger matching + rate limiting. Pure.
  Coach/
    AIProviding.swift          NEW  Protocol + ProviderID + errors
    OpenAIProvider.swift       NEW  The only networking file
    Secrets.swift              NEW  Reads the bundled plist
    CoachSettings.swift        NEW  @AppStorage-backed provider/speech toggles
  Support/
    CoachSpeaking.swift        NEW  Protocol + AVSpeechSynthesizer impl + route detection
  UI/
    CoachMessageView.swift     NEW  The overlay
    EffortPage.swift           MOD  Hosts the overlay
    WorkoutSessionModel.swift  MOD  brief at start, engine in pump, live cue at walk break
    SummaryView.swift          MOD  Post-run analysis
    SettingsView.swift         NEW  Provider + speech toggles
    HomeView.swift             MOD  Link to settings

FitBud Watch AppTests/
  CueTests.swift               NEW
  CoachEngineTests.swift       NEW  The heaviest suite in this plan
  CoachContextTests.swift      NEW
  OpenAIProviderTests.swift    NEW  Decoding only, no network
```

---

### Task 1: Secrets loading

**Files:**
- Create: `FitBud Watch App/Resources/Secrets.example.plist`
- Create: `FitBud Watch App/Coach/Secrets.swift`
- Modify: `.gitignore`
- Test: `FitBud Watch AppTests/CueTests.swift` (new file, first struct)

**Interfaces:**
- Consumes: nothing
- Produces: `Secrets.openAIKey: String?`, `Secrets.geminiKey: String?`, `Secrets.hasAnyKey: Bool`

- [ ] **Step 1: Gitignore the real key before writing any code**

Append to `.gitignore`:
```
# The real API keys. Secrets.example.plist documents the shape and IS committed.
Secrets.plist
```

Verify: `git check-ignore -v "FitBud Watch App/Resources/Secrets.plist"` must print a match.
Do this **first** — a key committed by accident cannot be un-committed from history without a rewrite.

- [ ] **Step 2: Write the example plist**

`FitBud Watch App/Resources/Secrets.example.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>OPENAI_API_KEY</key>
	<string></string>
	<key>GEMINI_API_KEY</key>
	<string></string>
</dict>
</plist>
```

- [ ] **Step 3: Write the loader**

`FitBud Watch App/Coach/Secrets.swift`:
```swift
import Foundation

/// Reads API keys from a gitignored `Secrets.plist` in the app bundle.
///
/// Not an `.xcconfig`, despite that being the obvious choice: this project has no
/// `baseConfigurationReference`, so an xcconfig would never be read, and adding
/// one means editing `project.pbxproj` — which Xcode rewrites cosmetically on
/// most builds, so a hand edit is easy to lose. A plist in `Resources/` is picked
/// up by the synchronized folder group automatically, the same way the training
/// plan JSON already is.
///
/// A key in an app bundle is readable by anyone holding the bundle. For a
/// personal sideloaded app that is an acceptable trade. It would not be for
/// anything distributed.
enum Secrets {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: String]
        else { return [:] }
        return dictionary
    }()

    /// `nil` rather than empty string when absent, so callers can use `if let`
    /// and an unconfigured app cleanly disables AI instead of sending a request
    /// with an empty bearer token.
    private static func value(_ key: String) -> String? {
        guard let value = values[key], !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        return value
    }

    static var openAIKey: String? { value("OPENAI_API_KEY") }
    static var geminiKey: String? { value("GEMINI_API_KEY") }
    static var hasAnyKey: Bool { openAIKey != nil || geminiKey != nil }
}
```

- [ ] **Step 4: Write the test**

`FitBud Watch AppTests/CueTests.swift`:
```swift
import Foundation
import Testing
@testable import FitBud_Watch_App

struct SecretsTests {
    @Test func missingOrEmptyKeysReadAsNil() {
        // No Secrets.plist is bundled in a test run, and an all-empty example
        // must not read as "configured" — otherwise the app would try to
        // authenticate with an empty bearer token and fail confusingly.
        #expect(Secrets.openAIKey == nil)
        #expect(Secrets.geminiKey == nil)
        #expect(Secrets.hasAnyKey == false)
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"`
Expected: PASS — **126 tests**.

- [ ] **Step 6: Commit**

```bash
git add .gitignore "FitBud Watch App/Resources/Secrets.example.plist" "FitBud Watch App/Coach/Secrets.swift" "FitBud Watch AppTests/CueTests.swift"
git commit -m "feat: read API keys from a gitignored bundled plist"
```

---

### Task 2: Cue model types

**Files:**
- Create: `FitBud Watch App/Models/Cue.swift`
- Test: `FitBud Watch AppTests/CueTests.swift` (append)

**Interfaces:**
- Consumes: `RunWalkPhase`
- Produces: `CueTrigger`, `CueUrgency`, `CueRule`, `Cue`, `SessionBrief`, `WorkoutAnalysis`, `CueRule.maxWords`

Foundation only.

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/CueTests.swift`:
```swift
struct CueRuleDecodingTests {
    private func decode(_ json: String) throws -> SessionBrief {
        try JSONDecoder().decode(SessionBrief.self, from: Data(json.utf8))
    }

    @Test func decodesAWellFormedBrief() throws {
        let brief = try decode("""
        {"opening":"Easy today. Let the walk breaks do the work.",
         "rules":[{"trigger":{"kind":"zoneAbove","zone":"Z2","sustainedSec":30},
                   "message":"Above easy. Ease off.","urgency":"immediate","repeats":true}]}
        """)
        #expect(brief.opening == "Easy today. Let the walk breaks do the work.")
        #expect(brief.rules.count == 1)
        #expect(brief.rules[0].trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30))
        #expect(brief.rules[0].urgency == .immediate)
        #expect(brief.rules[0].repeats)
    }

    @Test func rejectsAMessageLongerThanTwelveWords() {
        // Truncating mid-sentence would be worse than dropping the bundle:
        // a coach that stops speaking halfway through reads as broken.
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"halfway"},
             "message":"one two three four five six seven eight nine ten eleven twelve thirteen",
             "urgency":"atNextBreak","repeats":false}]}
            """)
        }
    }

    @Test func rejectsImmediateUrgencyOnANonZoneTrigger() {
        // Only drift warnings earn the right to interrupt a hard interval.
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"halfway"},
             "message":"Halfway there.","urgency":"immediate","repeats":false}]}
            """)
        }
    }

    @Test func rejectsAnUnknownTriggerKind() {
        #expect(throws: (any Error).self) {
            try decode("""
            {"opening":"Go","rules":[{"trigger":{"kind":"moonPhase"},
             "message":"Full moon.","urgency":"atNextBreak","repeats":false}]}
            """)
        }
    }

    @Test func decodesEveryTriggerKind() throws {
        let brief = try decode("""
        {"opening":"Go","rules":[
          {"trigger":{"kind":"zoneBelow","zone":"Z1","sustainedSec":60},"message":"Pick it up.","urgency":"immediate","repeats":true},
          {"trigger":{"kind":"splitCompleted"},"message":"Another one down.","urgency":"atNextBreak","repeats":true},
          {"trigger":{"kind":"splitCompleted","index":3},"message":"Three done.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"distanceReached","km":5},"message":"Five kilometres.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"elapsedReached","minutes":20},"message":"Twenty minutes in.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"phaseStarted","phase":"walk"},"message":"Walk break.","urgency":"atNextBreak","repeats":true},
          {"trigger":{"kind":"halfway"},"message":"Halfway.","urgency":"atNextBreak","repeats":false},
          {"trigger":{"kind":"finalKilometre"},"message":"Last one.","urgency":"atNextBreak","repeats":false}
        ]}
        """)
        #expect(brief.rules.count == 8)
        #expect(brief.rules[1].trigger == .splitCompleted(index: nil))
        #expect(brief.rules[2].trigger == .splitCompleted(index: 3))
        #expect(brief.rules[5].trigger == .phaseStarted(.walk))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: FAIL — `cannot find 'SessionBrief' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Models/Cue.swift`:
```swift
import Foundation

enum CueTrigger: Equatable, Sendable {
    case zoneAbove(ceiling: String, sustainedSec: TimeInterval)
    case zoneBelow(floor: String, sustainedSec: TimeInterval)
    /// `nil` index matches any split.
    case splitCompleted(index: Int?)
    case distanceReached(km: Double)
    case elapsedReached(minutes: Double)
    case phaseStarted(RunWalkPhase)
    case halfway
    case finalKilometre

    /// Only drift warnings may interrupt. Everything else waits for a walk
    /// break — a milestone delivered sixty seconds late is still a milestone,
    /// but one delivered mid-interval is an annoyance.
    var mayBeImmediate: Bool {
        switch self {
        case .zoneAbove, .zoneBelow: true
        default: false
        }
    }
}

extension CueTrigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, zone, sustainedSec, index, km, minutes, phase
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "zoneAbove":
            self = .zoneAbove(
                ceiling: try container.decode(String.self, forKey: .zone),
                sustainedSec: try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedSec) ?? 30
            )
        case "zoneBelow":
            self = .zoneBelow(
                floor: try container.decode(String.self, forKey: .zone),
                sustainedSec: try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedSec) ?? 60
            )
        case "splitCompleted":
            self = .splitCompleted(index: try container.decodeIfPresent(Int.self, forKey: .index))
        case "distanceReached":
            self = .distanceReached(km: try container.decode(Double.self, forKey: .km))
        case "elapsedReached":
            self = .elapsedReached(minutes: try container.decode(Double.self, forKey: .minutes))
        case "phaseStarted":
            let phase = try container.decode(String.self, forKey: .phase)
            self = .phaseStarted(phase == "run" ? .run : .walk)
        case "halfway":
            self = .halfway
        case "finalKilometre":
            self = .finalKilometre
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "Unknown cue trigger kind '\(kind)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .zoneAbove(zone, seconds):
            try container.encode("zoneAbove", forKey: .kind)
            try container.encode(zone, forKey: .zone)
            try container.encode(seconds, forKey: .sustainedSec)
        case let .zoneBelow(zone, seconds):
            try container.encode("zoneBelow", forKey: .kind)
            try container.encode(zone, forKey: .zone)
            try container.encode(seconds, forKey: .sustainedSec)
        case let .splitCompleted(index):
            try container.encode("splitCompleted", forKey: .kind)
            try container.encodeIfPresent(index, forKey: .index)
        case let .distanceReached(km):
            try container.encode("distanceReached", forKey: .kind)
            try container.encode(km, forKey: .km)
        case let .elapsedReached(minutes):
            try container.encode("elapsedReached", forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        case let .phaseStarted(phase):
            try container.encode("phaseStarted", forKey: .kind)
            try container.encode(phase == .run ? "run" : "walk", forKey: .phase)
        case .halfway:
            try container.encode("halfway", forKey: .kind)
        case .finalKilometre:
            try container.encode("finalKilometre", forKey: .kind)
        }
    }
}

enum CueUrgency: String, Codable, Equatable, Sendable {
    /// Interrupts, even mid-interval. Reserved for drift warnings.
    case immediate
    /// Queues until the next walk break.
    case atNextBreak
}

struct CueRule: Equatable, Sendable, Codable, Identifiable {
    /// Twelve words fits three lines at 20pt on a 46mm screen, and is about as
    /// much as anyone reads at running pace.
    static let maxWords = 12

    let id: UUID
    let trigger: CueTrigger
    let message: String
    let urgency: CueUrgency
    let repeats: Bool

    init(trigger: CueTrigger, message: String, urgency: CueUrgency = .atNextBreak, repeats: Bool = false) {
        self.id = UUID()
        self.trigger = trigger
        self.message = message
        self.urgency = urgency
        self.repeats = repeats
    }

    private enum CodingKeys: String, CodingKey {
        case trigger, message, urgency, repeats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The model does not supply ids; they exist only so the engine can
        // remember which non-repeating rules have already fired.
        id = UUID()
        trigger = try container.decode(CueTrigger.self, forKey: .trigger)
        message = try container.decode(String.self, forKey: .message)
        urgency = try container.decodeIfPresent(CueUrgency.self, forKey: .urgency) ?? .atNextBreak
        repeats = try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? false

        let words = message.split(whereSeparator: \.isWhitespace).count
        guard words <= Self.maxWords else {
            throw DecodingError.dataCorruptedError(
                forKey: .message, in: container,
                debugDescription: "Cue message is \(words) words; the limit is \(Self.maxWords)"
            )
        }
        guard urgency != .immediate || trigger.mayBeImmediate else {
            throw DecodingError.dataCorruptedError(
                forKey: .urgency, in: container,
                debugDescription: "Only zone triggers may be immediate"
            )
        }
    }
}

/// A cue the engine decided to deliver, with the rule it came from.
struct Cue: Equatable, Sendable, Identifiable {
    let id: UUID
    let message: String
    let urgency: CueUrgency
    /// Elapsed seconds into the workout when it fired.
    let firedAt: TimeInterval
}

struct SessionBrief: Equatable, Sendable, Decodable {
    /// Spoken and shown as the run begins.
    let opening: String
    let rules: [CueRule]
}

struct WorkoutAnalysis: Equatable, Sendable, Decodable {
    /// One or two sentences on how the run went.
    let summary: String
    /// One concrete thing to carry into the next session.
    let takeaway: String
}
```

- [ ] **Step 4: Run the tests**

Expected: PASS — **131 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/Cue.swift" "FitBud Watch AppTests/CueTests.swift"
git commit -m "feat: add cue rule model with strict decoding"
```

---

### Task 3: The default cue bundle

**Files:**
- Create: `FitBud Watch App/Models/DefaultCueBundle.swift`
- Test: `FitBud Watch AppTests/CueTests.swift` (append)

**Interfaces:**
- Consumes: `CueRule`, `CueTrigger`, `SessionBrief`, `PlanDay`
- Produces: `defaultBrief(targetZone: String, sessionTitle: String) -> SessionBrief`, `defaultBrief(for: PlanDay?) -> SessionBrief`

This is what plays whenever the model is unreachable — spec §3's table, verbatim. It is the offline experience, so it is specified rather than improvised.

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/CueTests.swift`:
```swift
struct DefaultCueBundleTests {
    @Test func buildsTheSixSpecifiedRules() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        #expect(brief.rules.count == 6)
        #expect(brief.opening.isEmpty == false)
    }

    @Test func theDriftWarningIsTheOnlyImmediateOne() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        let immediate = brief.rules.filter { $0.urgency == .immediate }
        #expect(immediate.count == 1)
        #expect(immediate[0].trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30))
    }

    @Test func theCeilingFollowsTheSessionsTargetZone() {
        // A tempo day's ceiling is Z3, not Z2 — warning an athlete off Z3
        // during a tempo session would be telling them not to do the workout.
        let brief = defaultBrief(targetZone: "Z3", sessionTitle: "Tempo")
        #expect(brief.rules.contains { $0.trigger == .zoneAbove(ceiling: "Z3", sustainedSec: 30) })
    }

    @Test func everyMessageIsWithinTheWordLimit() {
        for zone in ["Z1", "Z2", "Z3", "Z4"] {
            for rule in defaultBrief(targetZone: zone, sessionTitle: "Run").rules {
                #expect(rule.message.split(whereSeparator: \.isWhitespace).count <= CueRule.maxWords)
            }
        }
    }

    @Test func milestoneRulesFireOnlyOnce() {
        let brief = defaultBrief(targetZone: "Z2", sessionTitle: "Easy run")
        let halfway = brief.rules.first { $0.trigger == .halfway }
        let final = brief.rules.first { $0.trigger == .finalKilometre }
        #expect(halfway?.repeats == false)
        #expect(final?.repeats == false)
    }

    @Test func aPlanDayWithNoZoneFallsBackToZ2() throws {
        let plan = try PlanStore.loadBundled()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // 2026-08-03 is a rest day: no zone in the JSON.
        let restDay = plan.day(on: formatter.date(from: "2026-08-03")!)
        let brief = defaultBrief(for: restDay)
        #expect(brief.rules.contains { $0.trigger == .zoneAbove(ceiling: "Z2", sustainedSec: 30) })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `cannot find 'defaultBrief' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Models/DefaultCueBundle.swift`:
```swift
import Foundation

/// The coaching that plays when the model is unreachable.
///
/// Deliberately plain. Generic encouragement pretending to be personal is worse
/// than encouragement that is honestly generic — and this only ever plays when
/// the personal version could not be fetched.
func defaultBrief(targetZone: String, sessionTitle: String) -> SessionBrief {
    SessionBrief(
        opening: "\(sessionTitle). Keep it in \(targetZone) and let the walk breaks work.",
        rules: [
            CueRule(
                trigger: .zoneAbove(ceiling: targetZone, sustainedSec: 30),
                message: "Above easy. Ease off and let it come down.",
                urgency: .immediate,
                repeats: true
            ),
            CueRule(
                trigger: .zoneBelow(floor: "Z1", sustainedSec: 60),
                message: "You can pick it up a little.",
                repeats: true
            ),
            CueRule(trigger: .phaseStarted(.walk), message: "Walk break. Breathe.", repeats: true),
            CueRule(trigger: .splitCompleted(index: nil), message: "Another kilometre down.", repeats: true),
            CueRule(trigger: .halfway, message: "Halfway. Still feeling easy?"),
            CueRule(trigger: .finalKilometre, message: "Last kilometre. Finish strong.")
        ]
    )
}

/// Convenience for a plan day, defaulting the ceiling to Z2 when the day names
/// no zone — the plan's own default for easy running.
func defaultBrief(for day: PlanDay?) -> SessionBrief {
    defaultBrief(targetZone: day?.zone ?? "Z2", sessionTitle: day?.title ?? "Run")
}

extension SessionBrief {
    init(opening: String, rules: [CueRule]) {
        self.opening = opening
        self.rules = rules
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: PASS — **137 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/DefaultCueBundle.swift" "FitBud Watch AppTests/CueTests.swift"
git commit -m "feat: add the default offline cue bundle"
```

---

### Task 4: CoachEngine

**Files:**
- Create: `FitBud Watch App/Engine/CoachEngine.swift`
- Test: `FitBud Watch AppTests/CoachEngineTests.swift`

**Interfaces:**
- Consumes: `CueRule`, `Cue`, `CueTrigger`, `CueUrgency`, `WorkoutState`, `WorkoutEvent`, `HRZone`, `RunWalkPhase`
- Produces: `CoachEngine(brief:targetDistanceKm:)`, `mutating func evaluate(state:events:) -> Cue?`, `mutating func deliverQueued(at:) -> Cue?`, `var pendingCount: Int`

**This is the heart of the plan and takes the most tests.** Pure: no clock, no network, no HealthKit. All timing comes from `state.elapsed`.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/CoachEngineTests.swift`:
```swift
import Foundation
import Testing
@testable import FitBud_Watch_App

struct CoachEngineTests {
    private func state(
        elapsed: TimeInterval,
        hr: Double? = nil,
        km: Double = 0,
        phase: RunWalkPhase? = .run
    ) -> WorkoutState {
        var s = WorkoutState()
        s.elapsed = elapsed
        s.heartRate = hr
        s.currentZone = hr.flatMap(HRZone.zone(for:))
        s.distanceMeters = km * 1000
        s.runWalkPhase = phase
        return s
    }

    private func engine(_ rules: [CueRule], targetKm: Double = 10) -> CoachEngine {
        CoachEngine(brief: SessionBrief(opening: "Go", rules: rules), targetDistanceKm: targetKm)
    }

    // MARK: Trigger matching

    @Test func zoneAboveNeedsTheDriftSustained() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 30),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        // 175 is Z3 — above the Z2 ceiling — but only for a moment at first.
        #expect(e.evaluate(state: state(elapsed: 100, hr: 175), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 120, hr: 175), events: []) == nil)
        // 30s sustained: now it fires.
        #expect(e.evaluate(state: state(elapsed: 131, hr: 175), events: [])?.message == "Ease off.")
    }

    @Test func droppingBackIntoZoneResetsTheDriftClock() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 30),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        _ = e.evaluate(state: state(elapsed: 100, hr: 175), events: [])
        // Back into Z2 at 120 — the clock restarts, so 131 is only 11s of drift.
        _ = e.evaluate(state: state(elapsed: 120, hr: 155), events: [])
        _ = e.evaluate(state: state(elapsed: 125, hr: 175), events: [])
        #expect(e.evaluate(state: state(elapsed: 131, hr: 175), events: []) == nil)
    }

    @Test func splitTriggerFiresOnTheSplitEvent() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil),
                                message: "Another one.", repeats: true)])
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 540, duration: 540, heartRateAtSplit: 150)
        let cue = e.evaluate(state: state(elapsed: 540, hr: 150, km: 1, phase: .walk),
                             events: [.splitCompleted(split)])
        #expect(cue?.message == "Another one.")
    }

    @Test func anIndexedSplitTriggerIgnoresOtherSplits() {
        var e = engine([CueRule(trigger: .splitCompleted(index: 3), message: "Three.", repeats: false)])
        let first = Split(index: 1, distanceMeters: 1000, elapsed: 540, duration: 540, heartRateAtSplit: 150)
        #expect(e.evaluate(state: state(elapsed: 540, phase: .walk), events: [.splitCompleted(first)]) == nil)
    }

    @Test func halfwayUsesTheSessionTarget() {
        var e = engine([CueRule(trigger: .halfway, message: "Halfway.")], targetKm: 8)
        #expect(e.evaluate(state: state(elapsed: 600, km: 3.9, phase: .walk), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 620, km: 4.1, phase: .walk), events: [])?.message == "Halfway.")
    }

    @Test func finalKilometreFiresInsideTheLastKilometre() {
        var e = engine([CueRule(trigger: .finalKilometre, message: "Last one.")], targetKm: 8)
        #expect(e.evaluate(state: state(elapsed: 600, km: 6.5, phase: .walk), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 700, km: 7.2, phase: .walk), events: [])?.message == "Last one.")
    }

    @Test func phaseStartedFiresOnThePhaseChangeEvent() {
        var e = engine([CueRule(trigger: .phaseStarted(.walk), message: "Walk break.", repeats: true)])
        let cue = e.evaluate(state: state(elapsed: 300, phase: .walk), events: [.phaseChanged(.walk)])
        #expect(cue?.message == "Walk break.")
    }

    // MARK: Rate limiting — spec section 4

    @Test func aFlappingHeartRateProducesOneCueNotTwelve() {
        // The single most important test here. Without the 45s urgent floor a
        // heart rate hovering at the boundary would fire on every sample.
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 0),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        var fired = 0
        for second in stride(from: 0.0, through: 40.0, by: 1.0) {
            if e.evaluate(state: state(elapsed: second, hr: 175), events: []) != nil { fired += 1 }
        }
        #expect(fired == 1)
    }

    @Test func urgentCuesRespectTheFortyFiveSecondFloor() {
        var e = engine([CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 0),
                                message: "Ease off.", urgency: .immediate, repeats: true)])
        #expect(e.evaluate(state: state(elapsed: 0, hr: 175), events: []) != nil)
        #expect(e.evaluate(state: state(elapsed: 44, hr: 175), events: []) == nil)
        #expect(e.evaluate(state: state(elapsed: 46, hr: 175), events: []) != nil)
    }

    @Test func nonUrgentCuesWaitForAWalkBreak() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true)])
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        // Running: queued, not delivered.
        #expect(e.evaluate(state: state(elapsed: 300, km: 1, phase: .run), events: [.splitCompleted(split)]) == nil)
        #expect(e.pendingCount == 1)
        // Walk break: delivered.
        #expect(e.deliverQueued(at: 320)?.message == "Split.")
    }

    @Test func atMostOneCuePerWalkBreak() {
        var e = engine([
            CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true),
            CueRule(trigger: .halfway, message: "Halfway.")
        ], targetKm: 2)
        let split = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 300, km: 1.1, phase: .run), events: [.splitCompleted(split)])
        #expect(e.pendingCount == 2)
        #expect(e.deliverQueued(at: 310) != nil)
        // Second one waits for the *next* break rather than emptying the queue
        // into a single sixty-second window.
        #expect(e.deliverQueued(at: 320) == nil)
        #expect(e.pendingCount == 1)
    }

    @Test func ninetySecondsBetweenAnyTwoCues() {
        var e = engine([CueRule(trigger: .splitCompleted(index: nil), message: "Split.", repeats: true)])
        let one = Split(index: 1, distanceMeters: 1000, elapsed: 300, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 300, km: 1, phase: .run), events: [.splitCompleted(one)])
        #expect(e.deliverQueued(at: 300) != nil)

        let two = Split(index: 2, distanceMeters: 2000, elapsed: 600, duration: 300, heartRateAtSplit: 150)
        _ = e.evaluate(state: state(elapsed: 380, km: 2, phase: .run), events: [.splitCompleted(two)])
        #expect(e.deliverQueued(at: 380) == nil)   // only 80s since the last
        #expect(e.deliverQueued(at: 395) != nil)   // 95s
    }

    @Test func nonRepeatingRulesFireOnce() {
        var e = engine([CueRule(trigger: .phaseStarted(.walk), message: "Walk.", repeats: false)])
        #expect(e.evaluate(state: state(elapsed: 300, phase: .walk), events: [.phaseChanged(.walk)]) != nil)
        #expect(e.evaluate(state: state(elapsed: 600, phase: .walk), events: [.phaseChanged(.walk)]) == nil)
    }

    @Test func aStaleCueIsDroppedRatherThanDeliveredLate() {
        // "Halfway" arriving at 80% is worse than silence.
        var e = engine([CueRule(trigger: .halfway, message: "Halfway.")], targetKm: 10)
        _ = e.evaluate(state: state(elapsed: 600, km: 5.1, phase: .run), events: [])
        #expect(e.pendingCount == 1)
        #expect(e.deliverQueued(at: 780) == nil)   // 180s later: stale
        #expect(e.pendingCount == 0)
    }

    @Test func zoneCuesAreSuppressedDuringAWalkBreak() {
        // Heart rate is *supposed* to fall during a walk break, so a drift
        // warning there is noise. Spec section 12, question 1.
        var e = engine([CueRule(trigger: .zoneBelow(floor: "Z1", sustainedSec: 0),
                                message: "Pick it up.", urgency: .immediate, repeats: true)])
        #expect(e.evaluate(state: state(elapsed: 300, hr: 120, phase: .walk), events: []) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `cannot find 'CoachEngine' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Engine/CoachEngine.swift`:
```swift
import Foundation

/// Decides which cue to deliver and when.
///
/// Pure and deterministic: every timing decision comes from `state.elapsed`,
/// never from a clock, so a whole run can be replayed in a test in
/// milliseconds. This is the file that decides whether the coach feels like a
/// coach or like a nag, which is why it carries the heaviest test suite in the
/// project.
struct CoachEngine {
    /// Spec section 4.
    static let minimumGap: TimeInterval = 90
    static let urgentFloor: TimeInterval = 45
    /// A queued cue older than this has missed its moment and is dropped.
    static let staleAfter: TimeInterval = 120

    private let rules: [CueRule]
    private let targetDistanceKm: Double

    private var firedRuleIDs: Set<UUID> = []
    private var queued: [(rule: CueRule, queuedAt: TimeInterval)] = []
    private var lastDeliveredAt: TimeInterval?
    /// Elapsed at which the current zone excursion began, per rule.
    private var driftStartedAt: [UUID: TimeInterval] = [:]
    /// Walk-break identity, so "one cue per break" can be enforced without a clock.
    private var lastBreakServed: Int?
    private var breakCounter = 0
    private var lastPhase: RunWalkPhase?

    let opening: String

    init(brief: SessionBrief, targetDistanceKm: Double) {
        self.rules = brief.rules
        self.opening = brief.opening
        self.targetDistanceKm = max(targetDistanceKm, 0.1)
    }

    var pendingCount: Int { queued.count }

    /// Feeds one tick in. Returns a cue only if an urgent one fires now;
    /// non-urgent matches are queued for the next walk break.
    mutating func evaluate(state: WorkoutState, events: [WorkoutEvent]) -> Cue? {
        trackPhase(state)

        for rule in rules {
            guard !firedRuleIDs.contains(rule.id) || rule.repeats else { continue }
            guard matches(rule, state: state, events: events) else { continue }

            if rule.urgency == .immediate {
                guard canDeliver(at: state.elapsed, urgent: true) else { continue }
                return deliver(rule, at: state.elapsed)
            } else if !queued.contains(where: { $0.rule.id == rule.id }) {
                queued.append((rule, state.elapsed))
                markFired(rule)
            }
        }
        return nil
    }

    /// Called when the athlete is in a walk break. Delivers at most one queued
    /// cue, dropping any that have gone stale.
    mutating func deliverQueued(at elapsed: TimeInterval) -> Cue? {
        queued.removeAll { elapsed - $0.queuedAt > Self.staleAfter }
        guard lastBreakServed != breakCounter else { return nil }
        guard canDeliver(at: elapsed, urgent: false) else { return nil }
        guard !queued.isEmpty else { return nil }

        let next = queued.removeFirst()
        lastBreakServed = breakCounter
        return deliver(next.rule, at: elapsed)
    }

    // MARK: Private

    private mutating func trackPhase(_ state: WorkoutState) {
        if let phase = state.runWalkPhase, phase != lastPhase {
            if phase == .walk { breakCounter += 1 }
            lastPhase = phase
        }
    }

    private func canDeliver(at elapsed: TimeInterval, urgent: Bool) -> Bool {
        guard let last = lastDeliveredAt else { return true }
        return elapsed - last >= (urgent ? Self.urgentFloor : Self.minimumGap)
    }

    private mutating func deliver(_ rule: CueRule, at elapsed: TimeInterval) -> Cue {
        lastDeliveredAt = elapsed
        markFired(rule)
        return Cue(id: rule.id, message: rule.message, urgency: rule.urgency, firedAt: elapsed)
    }

    private mutating func markFired(_ rule: CueRule) {
        if !rule.repeats { firedRuleIDs.insert(rule.id) }
    }

    private mutating func matches(_ rule: CueRule, state: WorkoutState, events: [WorkoutEvent]) -> Bool {
        switch rule.trigger {
        case let .zoneAbove(ceiling, sustained):
            // Suppressed while walking: the heart rate is meant to be falling.
            guard state.runWalkPhase != .walk else { driftStartedAt[rule.id] = nil; return false }
            guard let zone = state.currentZone, let ceilingZone = zoneNamed(ceiling),
                  zone.lowerBPM > ceilingZone.lowerBPM
            else { driftStartedAt[rule.id] = nil; return false }
            return sustainedLongEnough(rule.id, since: state.elapsed, needed: sustained)

        case let .zoneBelow(floor, sustained):
            guard state.runWalkPhase != .walk else { driftStartedAt[rule.id] = nil; return false }
            guard let floorZone = zoneNamed(floor) else { return false }
            let below = state.currentZone.map { $0.lowerBPM < floorZone.lowerBPM } ?? (state.heartRate != nil)
            guard below else { driftStartedAt[rule.id] = nil; return false }
            return sustainedLongEnough(rule.id, since: state.elapsed, needed: sustained)

        case let .splitCompleted(index):
            return events.contains { event in
                guard case let .splitCompleted(split) = event else { return false }
                return index == nil || split.index == index
            }

        case let .distanceReached(km):
            return state.distanceKm >= km

        case let .elapsedReached(minutes):
            return state.elapsed >= minutes * 60

        case let .phaseStarted(phase):
            return events.contains { $0 == .phaseChanged(phase) }

        case .halfway:
            return state.distanceKm >= targetDistanceKm / 2

        case .finalKilometre:
            return state.distanceKm >= max(targetDistanceKm - 1, 0)
        }
    }

    private func zoneNamed(_ id: String) -> HRZone? {
        HRZone.table.first { $0.id == id }
    }

    private mutating func sustainedLongEnough(
        _ ruleID: UUID, since elapsed: TimeInterval, needed: TimeInterval
    ) -> Bool {
        guard let start = driftStartedAt[ruleID] else {
            driftStartedAt[ruleID] = elapsed
            return needed <= 0
        }
        return elapsed - start >= needed
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: PASS — **152 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Engine/CoachEngine.swift" "FitBud Watch AppTests/CoachEngineTests.swift"
git commit -m "feat: add CoachEngine with trigger matching and rate limiting"
```

---

### Task 5: Coach context

**Files:**
- Create: `FitBud Watch App/Models/CoachContext.swift`
- Test: `FitBud Watch AppTests/CoachContextTests.swift`

**Interfaces:**
- Consumes: `PlanDay`, `BlockProgress`, `HistoricRun`, `WorkoutState`, `HRZone`, `Split`
- Produces: `CoachContext`, `LiveCoachContext`, `CoachContext.promptSummary: String`, `LiveCoachContext.promptSummary: String`

Foundation only. Both types are plain data plus one function that renders them into the compact text the model is sent — which is what keeps the payload cheap and is worth testing, because a silently empty prompt would produce plausible but useless coaching.

- [ ] **Step 1: Write the failing tests**

`FitBud Watch AppTests/CoachContextTests.swift`:
```swift
import Foundation
import Testing
@testable import FitBud_Watch_App

struct CoachContextTests {
    private func sampleContext() -> CoachContext {
        CoachContext(
            sessionTitle: "Long run 5:1",
            sessionNotes: "Take the walk breaks from minute one.",
            targetKm: 14,
            targetZone: "Z2",
            runWalk: "run 5min / walk 1min",
            daysToRace: 53,
            weekIndex: 5,
            totalWeeks: 8,
            weekFocus: "Biggest jump of the block.",
            weekCompletedKm: 12,
            weekPlannedKm: 26,
            easyShare: 0.66,
            recentRuns: [
                "2026-08-04: 4.0km at 9:12/km, avg 158bpm (Z2)",
                "2026-08-06: 4.1km at 8:50/km, avg 171bpm (Z3)"
            ],
            sleepHours: 5.2,
            restingHeartRate: 66,
            hrv: 41,
            zoneTable: "Z1 133-148, Z2 148-163, Z3 163-177, Z4 177-192, Z5 192-207"
        )
    }

    @Test func promptSummaryNamesTheSessionAndTheTarget() {
        let text = sampleContext().promptSummary
        #expect(text.contains("Long run 5:1"))
        #expect(text.contains("14"))
        #expect(text.contains("Z2"))
    }

    @Test func promptSummaryCarriesRecoveryAndRaceCountdown() {
        let text = sampleContext().promptSummary
        #expect(text.contains("53"))
        #expect(text.contains("5.2"))
        #expect(text.contains("66"))
    }

    @Test func promptSummaryStatesTheEasyShareAsAPercentage() {
        // The 80% rule is the point of the whole plan; the model must see the
        // number in a form it will not misread as a fraction of one.
        #expect(sampleContext().promptSummary.contains("66%"))
    }

    @Test func missingRecoveryDataIsOmittedRatherThanSentAsZero() {
        // A zero resting heart rate would read as a medical emergency.
        var context = sampleContext()
        context.sleepHours = nil
        context.restingHeartRate = nil
        context.hrv = nil
        let text = context.promptSummary
        #expect(!text.contains("Sleep"))
        #expect(!text.contains("Resting HR"))
    }

    @Test func liveSummaryCarriesSplitsAndZoneTime() {
        let live = LiveCoachContext(
            elapsedSeconds: 1200,
            distanceKm: 3.2,
            splitPaces: ["9:05", "9:20", "8:58"],
            timeInZoneSeconds: ["Z1": 120, "Z2": 900, "Z3": 180],
            currentZone: "Z2",
            currentHeartRate: 156,
            walkBreakNumber: 4
        )
        let text = live.promptSummary
        #expect(text.contains("9:20"))
        #expect(text.contains("Z2"))
        #expect(text.contains("3.2"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `cannot find 'CoachContext' in scope`.

- [ ] **Step 3: Write the implementation**

`FitBud Watch App/Models/CoachContext.swift`:
```swift
import Foundation

/// Everything the model is told before a run.
///
/// Rendered to compact text rather than sent as JSON: the model reads prose
/// better than it reads schemas, and this keeps the payload small enough that
/// cost never becomes a design constraint.
struct CoachContext: Equatable, Sendable {
    var sessionTitle: String
    var sessionNotes: String
    var targetKm: Double
    var targetZone: String
    var runWalk: String?

    var daysToRace: Int
    var weekIndex: Int
    var totalWeeks: Int
    var weekFocus: String
    var weekCompletedKm: Double
    var weekPlannedKm: Double
    /// 0…1, or nil when there is nothing to judge yet.
    var easyShare: Double?

    var recentRuns: [String]

    var sleepHours: Double?
    var restingHeartRate: Double?
    var hrv: Double?

    var zoneTable: String

    var promptSummary: String {
        var lines: [String] = []
        lines.append("Today's session: \(sessionTitle), target \(fmt(targetKm))km in \(targetZone).")
        if let runWalk { lines.append("Run/walk: \(runWalk).") }
        if !sessionNotes.isEmpty { lines.append("Plan note: \(sessionNotes)") }
        lines.append("Week \(weekIndex) of \(totalWeeks), \(daysToRace) days to race day. Focus: \(weekFocus)")
        lines.append("This week: \(fmt(weekCompletedKm))km of \(fmt(weekPlannedKm))km planned.")
        if let easyShare {
            lines.append("Easy running this week: \(Int((easyShare * 100).rounded()))% of runs (target 80%).")
        }
        if !recentRuns.isEmpty {
            lines.append("Recent runs:")
            lines.append(contentsOf: recentRuns.map { "  \($0)" })
        }
        // Omitted rather than zeroed when absent: a resting heart rate of 0
        // would read as a medical emergency.
        if let sleepHours { lines.append("Sleep last night: \(String(format: "%.1f", sleepHours))h.") }
        if let restingHeartRate { lines.append("Resting HR: \(Int(restingHeartRate))bpm.") }
        if let hrv { lines.append("HRV: \(Int(hrv))ms.") }
        lines.append("Zones: \(zoneTable)")
        return lines.joined(separator: "\n")
    }

    private func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The much smaller payload sent at a walk break.
struct LiveCoachContext: Equatable, Sendable {
    var elapsedSeconds: TimeInterval
    var distanceKm: Double
    var splitPaces: [String]
    var timeInZoneSeconds: [String: TimeInterval]
    var currentZone: String?
    var currentHeartRate: Double?
    var walkBreakNumber: Int

    var promptSummary: String {
        var lines: [String] = []
        lines.append("\(formatDuration(elapsedSeconds)) elapsed, \(String(format: "%.2f", distanceKm))km covered.")
        if !splitPaces.isEmpty {
            lines.append("Splits so far: \(splitPaces.joined(separator: ", "))")
        }
        let zones = HRZone.table
            .compactMap { zone -> String? in
                guard let seconds = timeInZoneSeconds[zone.id], seconds > 0 else { return nil }
                return "\(zone.id) \(formatPace(seconds))"
            }
        if !zones.isEmpty { lines.append("Time in zone: \(zones.joined(separator: ", "))") }
        if let currentZone, let currentHeartRate {
            lines.append("Right now: \(Int(currentHeartRate))bpm, \(currentZone).")
        }
        lines.append("This is walk break \(walkBreakNumber).")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run the tests**

Expected: PASS — **157 tests**.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/Models/CoachContext.swift" "FitBud Watch AppTests/CoachContextTests.swift"
git commit -m "feat: add coach context types"
```

---

### Task 6: AIProviding and the OpenAI provider

**Files:**
- Create: `FitBud Watch App/Coach/AIProviding.swift`
- Create: `FitBud Watch App/Coach/OpenAIProvider.swift`
- Test: `FitBud Watch AppTests/OpenAIProviderTests.swift`

**Interfaces:**
- Consumes: `CoachContext`, `LiveCoachContext`, `SessionBrief`, `WorkoutAnalysis`, `CompletedWorkout`, `Secrets`
- Produces: `ProviderID`, `AIProvidingError`, `protocol AIProviding`, `OpenAIProvider(apiKey:session:)`, `OpenAIProvider.model`

Tests cover **decoding only** — no network. The HTTP call itself is verified on device.

- [ ] **Step 1: Write the protocol**

`FitBud Watch App/Coach/AIProviding.swift`:
```swift
import Foundation

enum ProviderID: String, CaseIterable, Sendable {
    case openAI, gemini

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Gemini"
        }
    }
}

enum AIProvidingError: LocalizedError {
    case notConfigured
    case badResponse(Int)
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No API key is configured."
        case let .badResponse(code): "The coach service returned \(code)."
        case let .undecodable(detail): "The coach's reply couldn't be read: \(detail)"
        }
    }
}

/// The seam every AI call goes through.
///
/// Nothing above this protocol knows which provider is in use, and nothing
/// below it touches the workout. Every method may fail; every caller has a
/// fallback that keeps the run recording.
protocol AIProviding: Sendable {
    var id: ProviderID { get }
    func brief(context: CoachContext) async throws -> SessionBrief
    func liveCue(context: LiveCoachContext) async throws -> String
    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis
}
```

- [ ] **Step 2: Write the failing decoding tests**

`FitBud Watch AppTests/OpenAIProviderTests.swift`:
```swift
import Foundation
import Testing
@testable import FitBud_Watch_App

struct OpenAIResponseDecodingTests {
    @Test func extractsTheAssistantMessageContent() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"Nice and easy today."}}]}
        """
        let text = try OpenAIProvider.extractContent(from: Data(json.utf8))
        #expect(text == "Nice and easy today.")
    }

    @Test func throwsWhenThereAreNoChoices() {
        #expect(throws: (any Error).self) {
            try OpenAIProvider.extractContent(from: Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test func decodesABriefFromTheAssistantContent() throws {
        // The model returns the brief as a JSON *string* inside the message,
        // so this is a two-stage decode and each stage can fail separately.
        let inner = #"{\"opening\":\"Easy today.\",\"rules\":[{\"trigger\":{\"kind\":\"halfway\"},\"message\":\"Halfway there.\",\"urgency\":\"atNextBreak\",\"repeats\":false}]}"#
        let json = "{\"choices\":[{\"message\":{\"content\":\"\(inner)\"}}]}"
        let brief = try OpenAIProvider.decodeBrief(from: Data(json.utf8))
        #expect(brief.opening == "Easy today.")
        #expect(brief.rules.count == 1)
    }

    @Test func aBriefWithAnOverlongMessageIsRejectedWholesale() {
        // Never partially applied: a half-valid bundle would coach
        // inconsistently, which is worse than falling back to the default.
        let inner = #"{\"opening\":\"Go\",\"rules\":[{\"trigger\":{\"kind\":\"halfway\"},\"message\":\"one two three four five six seven eight nine ten eleven twelve thirteen\",\"urgency\":\"atNextBreak\",\"repeats\":false}]}"#
        let json = "{\"choices\":[{\"message\":{\"content\":\"\(inner)\"}}]}"
        #expect(throws: (any Error).self) {
            try OpenAIProvider.decodeBrief(from: Data(json.utf8))
        }
    }

    @Test func theModelIdentifierIsASingleConstant() {
        #expect(OpenAIProvider.model == "gpt-5-mini")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Expected: FAIL — `cannot find 'OpenAIProvider' in scope`.

- [ ] **Step 4: Write the provider**

`FitBud Watch App/Coach/OpenAIProvider.swift`:
```swift
import Foundation

/// The only file in the app that makes a network request.
struct OpenAIProvider: AIProviding {
    /// One place to change the model. `gpt-5-mini` is fast, cheap, and supports
    /// strict structured output, which is what makes the cue bundle safe to
    /// decode rather than hopeful.
    static let model = "gpt-5-mini"

    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    let id: ProviderID = .openAI
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    private static let systemPrompt = """
    You are a running coach speaking to one athlete through their Apple Watch mid-run.
    Be specific and warm. Never generic. Use their actual numbers.
    Every message you write is read at running pace: at most 12 words, no punctuation
    beyond a full stop or question mark, no emoji, no exclamation marks.
    The athlete's plan requires 80% of running easy; every run in their history was too hard.
    Your job is to keep them honest about that without nagging.
    """

    func brief(context: CoachContext) async throws -> SessionBrief {
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                Write the coaching for this session: one opening line, and 4 to 7 cue rules.
                Only zoneAbove and zoneBelow rules may have urgency "immediate".
                """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "session_brief", "strict": true, "schema": Self.briefSchema]
            ]
        ]
        let data = try await post(body)
        return try Self.decodeBrief(from: data)
    }

    func liveCue(context: LiveCoachContext) async throws -> String {
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                Say one thing to the athlete right now. At most 12 words. Plain text only.
                """]
            ]
        ]
        let data = try await post(body)
        return try Self.extractContent(from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
        let distance = String(format: "%.2f", workout.distanceMeters / 1000)
        let pace = workout.averagePaceSecPerKm.map(formatPace) ?? "unknown"
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": """
                \(context.promptSummary)

                They just finished: \(distance)km in \(formatDuration(workout.duration)), \
                average pace \(pace)/km, average heart rate \
                \(workout.averageHeartRate.map { String(Int($0)) } ?? "unknown")bpm.

                Write a two-sentence summary and one concrete takeaway for next time.
                """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "workout_analysis", "strict": true, "schema": Self.analysisSchema]
            ]
        ]
        let data = try await post(body)
        let content = try Self.extractContent(from: data)
        return try JSONDecoder().decode(WorkoutAnalysis.self, from: Data(content.utf8))
    }

    // MARK: Transport

    private func post(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Short by design: a coaching line that arrives late is worthless, and
        // the caller always has a bundled cue to fall back on.
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIProvidingError.badResponse(0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIProvidingError.badResponse(http.statusCode)
        }
        return data
    }

    // MARK: Decoding — pure, and unit tested

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    static func extractContent(from data: Data) throws -> String {
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw AIProvidingError.undecodable("no choices in response")
        }
        return content
    }

    static func decodeBrief(from data: Data) throws -> SessionBrief {
        let content = try extractContent(from: data)
        do {
            return try JSONDecoder().decode(SessionBrief.self, from: Data(content.utf8))
        } catch {
            // Rejected wholesale rather than partially applied: a half-valid
            // bundle would coach inconsistently, which is worse than the
            // default bundle playing.
            throw AIProvidingError.undecodable(error.localizedDescription)
        }
    }

    // MARK: Schemas

    private static let briefSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["opening", "rules"],
        "properties": [
            "opening": ["type": "string"],
            "rules": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["trigger", "message", "urgency", "repeats"],
                    "properties": [
                        "trigger": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["kind"],
                            "properties": [
                                "kind": ["type": "string", "enum": [
                                    "zoneAbove", "zoneBelow", "splitCompleted", "distanceReached",
                                    "elapsedReached", "phaseStarted", "halfway", "finalKilometre"
                                ]],
                                "zone": ["type": "string"],
                                "sustainedSec": ["type": "number"],
                                "index": ["type": "integer"],
                                "km": ["type": "number"],
                                "minutes": ["type": "number"],
                                "phase": ["type": "string", "enum": ["run", "walk"]]
                            ]
                        ],
                        "message": ["type": "string"],
                        "urgency": ["type": "string", "enum": ["immediate", "atNextBreak"]],
                        "repeats": ["type": "boolean"]
                    ]
                ]
            ]
        ]
    ]

    private static let analysisSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "takeaway"],
        "properties": [
            "summary": ["type": "string"],
            "takeaway": ["type": "string"]
        ]
    ]
}
```

- [ ] **Step 5: Run the tests**

Expected: PASS — **162 tests**.

- [ ] **Step 6: Commit**

```bash
git add "FitBud Watch App/Coach/AIProviding.swift" "FitBud Watch App/Coach/OpenAIProvider.swift" "FitBud Watch AppTests/OpenAIProviderTests.swift"
git commit -m "feat: add AIProviding seam and the OpenAI provider"
```

---

### Task 7: Speech

**Files:**
- Create: `FitBud Watch App/Support/CoachSpeaking.swift`
- Create: `FitBud Watch App/Coach/CoachSettings.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `protocol CoachSpeaking`, `WatchCoachSpeaker()`, `CoachSettings` with `isSpeechEnabled`, `providerID`

No unit tests: `AVSpeechSynthesizer` and `AVAudioSession` cannot be meaningfully exercised in a test bundle. Verified on device. Keeping both types this thin is what makes that acceptable.

- [ ] **Step 1: Write the speaker**

`FitBud Watch App/Support/CoachSpeaking.swift`:
```swift
import AVFoundation
import Foundation

protocol CoachSpeaking {
    /// True only when a Bluetooth or AirPlay route is connected.
    var canBeHeard: Bool { get }
    func speak(_ text: String)
    func stop()
}

/// Speaks coaching through connected headphones.
///
/// Deliberately silent on the watch's own speaker: it cannot compete with wind
/// and road noise at 9 min/km, and a coach that shouts into that is a coach the
/// athlete stops trusting. With nothing paired the message is still shown and
/// still buzzes.
final class WatchCoachSpeaker: NSObject, CoachSpeaking {
    private let synthesizer = AVSpeechSynthesizer()

    var canBeHeard: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .headphones:
                true
            default:
                false
            }
        }
    }

    func speak(_ text: String) {
        guard canBeHeard else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Ducks music rather than stopping it.
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            return
        }
        // A new cue replaces the old one rather than queueing behind it: stale
        // coaching spoken over fresh coaching is worse than either alone.
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        // Slightly below default: clearer at effort, and the athlete is
        // breathing hard.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// Used in tests and previews.
struct SilentCoachSpeaker: CoachSpeaking {
    var canBeHeard: Bool { false }
    func speak(_ text: String) {}
    func stop() {}
}
```

- [ ] **Step 2: Write the settings store**

`FitBud Watch App/Coach/CoachSettings.swift`:
```swift
import Foundation
import Observation

/// User-facing coaching preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class CoachSettings {
    private enum Keys {
        static let speech = "coach.speechEnabled"
        static let provider = "coach.providerID"
    }

    /// Defaults on: the athlete usually runs with AirPods, and the speaker
    /// stays silent by itself when nothing is paired.
    var isSpeechEnabled: Bool {
        didSet { UserDefaults.standard.set(isSpeechEnabled, forKey: Keys.speech) }
    }

    var providerID: ProviderID {
        didSet { UserDefaults.standard.set(providerID.rawValue, forKey: Keys.provider) }
    }

    init() {
        let defaults = UserDefaults.standard
        isSpeechEnabled = defaults.object(forKey: Keys.speech) as? Bool ?? true
        providerID = (defaults.string(forKey: Keys.provider).flatMap(ProviderID.init(rawValue:))) ?? .openAI
    }

    /// The provider to use, or `nil` when no key is configured — in which case
    /// the app is the tracker it already was.
    func makeProvider() -> (any AIProviding)? {
        switch providerID {
        case .openAI:
            guard let key = Secrets.openAIKey else { return nil }
            return OpenAIProvider(apiKey: key)
        case .gemini:
            // Gemini sits behind the same seam and needs no change above it.
            // Implemented after OpenAI is proven on a real run.
            return nil
        }
    }
}
```

- [ ] **Step 3: Verify it compiles**

Run the test command. Expected: PASS — **162 tests**, no compile errors.

- [ ] **Step 4: Commit**

```bash
git add "FitBud Watch App/Support/CoachSpeaking.swift" "FitBud Watch App/Coach/CoachSettings.swift"
git commit -m "feat: add coach speech and settings"
```

---

### Task 8: The message overlay

**Files:**
- Create: `FitBud Watch App/UI/CoachMessageView.swift`
- Modify: `FitBud Watch App/UI/EffortPage.swift`

**Interfaces:**
- Consumes: `Cue`, `Theme`
- Produces: `CoachMessageView(message:onDismiss:)`

- [ ] **Step 1: Write the overlay**

`FitBud Watch App/UI/CoachMessageView.swift`:
```swift
import SwiftUI

/// A coaching line, over the ring.
///
/// Covering the ring is safe rather than a compromise: `EffortPage` sets a
/// `.containerBackground` wash that tracks the live zone, so green behind the
/// words still means green. The safety signal survives the message sitting on
/// top of it.
///
/// It could not live *inside* the ring in any case — the clear chord at the
/// label's height is about 82pt, which "WARMING UP" barely fits. There is no
/// room for a sentence.
struct CoachMessageView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dims the ring rather than hiding it: the zone wash still reads
            // through, and the text has something to sit on.
            Color.black.opacity(0.55)

            Text(message)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                // 12 words fits three lines at 20pt on a 46mm screen. The scale
                // factor is a guard for an over-length line, so it shrinks
                // rather than truncating mid-sentence.
                .minimumScaleFactor(0.7)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
        }
        .ignoresSafeArea()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onTapGesture(perform: onDismiss)
    }
}
```

- [ ] **Step 2: Host it on the Effort page**

In `FitBud Watch App/UI/EffortPage.swift`, wrap the existing `ZStack` contents. Add after the centre `VStack` (still inside the outer `ZStack`, so it draws on top):

```swift
            if let cue = model.currentCue {
                CoachMessageView(message: cue.message) {
                    model.dismissCue()
                }
            }
```

and add to the outer `ZStack`'s modifiers, alongside the existing `.animation`:

```swift
        .animation(.easeInOut(duration: 0.25), value: model.currentCue)
```

- [ ] **Step 3: Verify it compiles**

`model.currentCue` and `model.dismissCue()` arrive in Task 9, so this step will not compile until then. **Write both files now, and expect the build to fail here** — Task 9 completes the pair. Confirm the failure is exactly `value of type 'WorkoutSessionModel' has no member 'currentCue'` and nothing else, then move on.

- [ ] **Step 4: Do not commit yet**

This task's files are committed together with Task 9, because neither compiles without the other.

---

### Task 9: Wire the coach into the session

**Files:**
- Modify: `FitBud Watch App/UI/WorkoutSessionModel.swift`
- Test: `FitBud Watch AppTests/CoachEngineTests.swift` (append)

**Interfaces:**
- Consumes: `CoachEngine`, `SessionBrief`, `defaultBrief(for:)`, `AIProviding`, `CoachSpeaking`, `CoachSettings`, `CoachContext`, `LiveCoachContext`, `PlanStore`
- Produces: `WorkoutSessionModel.currentCue: Cue?`, `.dismissCue()`, `.configureCoach(provider:speaker:settings:)`

- [ ] **Step 1: Write the failing tests**

Append to `FitBud Watch AppTests/CoachEngineTests.swift`:
```swift
@MainActor
struct CoachWiringTests {
    /// Returns a brief immediately; records what it was asked for.
    final class FakeProvider: AIProviding, @unchecked Sendable {
        let id: ProviderID = .openAI
        var briefToReturn: SessionBrief?
        var briefError: (any Error)?
        private(set) var briefCallCount = 0

        func brief(context: CoachContext) async throws -> SessionBrief {
            briefCallCount += 1
            if let briefError { throw briefError }
            return briefToReturn ?? SessionBrief(opening: "Go", rules: [])
        }
        func liveCue(context: LiveCoachContext) async throws -> String { "Keep going." }
        func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
            WorkoutAnalysis(summary: "Good run.", takeaway: "Keep it easy.")
        }
    }

    final class RecordingSpeaker: CoachSpeaking, @unchecked Sendable {
        var canBeHeard = true
        private(set) var spoken: [String] = []
        func speak(_ text: String) { spoken.append(text) }
        func stop() {}
    }

    @Test func aFailedBriefStillLeavesTheCoachWorking() async {
        // The run must never be blocked or left silent by an AI failure.
        let provider = FakeProvider()
        provider.briefError = AIProvidingError.badResponse(500)
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: provider, speaker: RecordingSpeaker(), settings: CoachSettings())

        await model.start(.openEasyRun)
        // The default bundle is in place, so cues can still fire.
        #expect(model.coachIsReady)
    }

    @Test func aCueIsSpokenOnlyWhenSpeechIsEnabled() {
        let speaker = RecordingSpeaker()
        let settings = CoachSettings()
        settings.isSpeechEnabled = false
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: speaker, settings: settings)

        model.present(Cue(id: UUID(), message: "Ease off.", urgency: .immediate, firedAt: 100))
        #expect(model.currentCue?.message == "Ease off.")
        #expect(speaker.spoken.isEmpty)

        settings.isSpeechEnabled = true
        model.present(Cue(id: UUID(), message: "Walk break.", urgency: .atNextBreak, firedAt: 200))
        #expect(speaker.spoken == ["Walk break."])
    }

    @Test func dismissingClearsTheMessage() {
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: RecordingSpeaker(), settings: CoachSettings())
        model.present(Cue(id: UUID(), message: "Halfway.", urgency: .atNextBreak, firedAt: 100))
        #expect(model.currentCue != nil)
        model.dismissCue()
        #expect(model.currentCue == nil)
    }

    @Test func resetClearsCoachState() {
        let model = WorkoutSessionModel(recorder: FakeWorkoutRecorder(), haptics: SilentHaptics())
        model.configureCoach(provider: FakeProvider(), speaker: RecordingSpeaker(), settings: CoachSettings())
        model.present(Cue(id: UUID(), message: "Halfway.", urgency: .atNextBreak, firedAt: 100))
        model.reset()
        #expect(model.currentCue == nil)
        #expect(model.coachIsReady == false)
    }
}

/// A haptic player that does nothing, for tests that are not about haptics.
struct SilentHaptics: HapticPlaying {
    func play(_ haptic: WorkoutHaptic) {}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `value of type 'WorkoutSessionModel' has no member 'configureCoach'`.

- [ ] **Step 3: Add coach state to the model**

In `FitBud Watch App/UI/WorkoutSessionModel.swift`, add these stored properties beside the existing ones:

```swift
    private(set) var currentCue: Cue?
    /// True once a brief — real or default — is loaded and cues can fire.
    private(set) var coachIsReady = false

    private var coachEngine: CoachEngine?
    private var provider: (any AIProviding)?
    private var speaker: (any CoachSpeaking)?
    private var settings: CoachSettings?
    private var liveCueTask: Task<Void, Never>?
    private var lastServedBreak: Int?
    private var dismissTask: Task<Void, Never>?
    /// Incremented on each transition into a walk phase, so "one live call per
    /// break" holds for any run/walk ratio.
    private var walkBreakCounter = 0
    private var lastCoachPhase: RunWalkPhase?
```

Add the configuration entry point and cue presentation:

```swift
    /// Injected once at app start. Kept separate from `init` so tests can
    /// construct a model without a coach at all.
    func configureCoach(provider: (any AIProviding)?, speaker: any CoachSpeaking, settings: CoachSettings) {
        self.provider = provider
        self.speaker = speaker
        self.settings = settings
    }

    /// Shows a cue, buzzes, and speaks it when speech is on and something is
    /// paired to hear it.
    func present(_ cue: Cue) {
        currentCue = cue
        haptics.play(.splitCompleted)
        if settings?.isSpeechEnabled == true {
            speaker?.speak(cue.message)
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.currentCue = nil
        }
    }

    func dismissCue() {
        dismissTask?.cancel()
        dismissTask = nil
        currentCue = nil
        speaker?.stop()
    }
```

- [ ] **Step 4: Load the brief when a workout starts**

At the end of `start(_:)`'s success path, after `pump(metrics)`, add:

```swift
            loadBrief(for: configuration)
```

and add the method:

```swift
    /// Fetches the session brief in the background. The run has already
    /// started by the time this is called — coaching is never on the critical
    /// path, and a failure falls back to the default bundle rather than
    /// leaving the athlete uncoached.
    private func loadBrief(for configuration: WorkoutConfiguration) {
        let planDay = (try? PlanStore.loadBundled())?.day(on: Date())
        let fallback = defaultBrief(for: planDay)
        let targetKm = planDay?.targetKm ?? 5

        coachEngine = CoachEngine(brief: fallback, targetDistanceKm: targetKm)
        coachIsReady = true

        guard let provider, let context = CoachContextBuilder.build(planDay: planDay) else { return }
        Task { [weak self] in
            guard let brief = try? await provider.brief(context: context) else { return }
            guard let self, self.phase == .running || self.phase == .paused else { return }
            self.coachEngine = CoachEngine(brief: brief, targetDistanceKm: targetKm)
            if !brief.opening.isEmpty {
                self.present(Cue(id: UUID(), message: brief.opening, urgency: .atNextBreak, firedAt: 0))
            }
        }
    }
```

- [ ] **Step 5: Evaluate cues in the metric pump**

In `apply(engine:events:)`, after `state = engine.state`, add:

```swift
        evaluateCoach(events: events)
```

and add:

```swift
    private func evaluateCoach(events: [WorkoutEvent]) {
        if let phase = state.runWalkPhase, phase != lastCoachPhase {
            if phase == .walk { walkBreakCounter += 1 }
            lastCoachPhase = phase
        }
        guard var coachEngine else { return }
        if let cue = coachEngine.evaluate(state: state, events: events) {
            present(cue)
        } else if state.runWalkPhase == .walk, let cue = coachEngine.deliverQueued(at: state.elapsed) {
            present(cue)
        }
        self.coachEngine = coachEngine
        requestLiveCueIfAtNewWalkBreak()
    }

    /// Fires at most one live call per walk break. The athlete is easing off
    /// for sixty seconds, the phone is in a pocket, and a two-second response
    /// lands comfortably inside that window — which is the only reason a
    /// network call is acceptable during a run at all.
    private func requestLiveCueIfAtNewWalkBreak() {
        guard state.runWalkPhase == .walk, let provider else { return }
        // Counted by observing the transition into `.walk`, not derived from
        // elapsed: the cycle length differs per session (4:1 through week 4,
        // 5:1 from week 5), so any hardcoded divisor would fire at the wrong
        // moments on half the plan.
        guard lastServedBreak != walkBreakCounter else { return }
        lastServedBreak = walkBreakCounter
        let breakNumber = walkBreakCounter

        let context = LiveCoachContext(
            elapsedSeconds: state.elapsed,
            distanceKm: state.distanceKm,
            splitPaces: state.splits.map { formatPace($0.paceSecPerKm) },
            timeInZoneSeconds: state.timeInZone,
            currentZone: state.currentZone?.id,
            currentHeartRate: state.heartRate,
            walkBreakNumber: breakNumber
        )
        liveCueTask?.cancel()
        liveCueTask = Task { [weak self] in
            guard let message = try? await provider.liveCue(context: context), !message.isEmpty else { return }
            guard let self, self.currentCue == nil, self.phase == .running else { return }
            self.present(Cue(id: UUID(), message: message, urgency: .atNextBreak, firedAt: self.state.elapsed))
        }
    }
```

- [ ] **Step 6: Clear coach state in `reset()`**

Add to `reset()`:

```swift
        liveCueTask?.cancel()
        liveCueTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        coachEngine = nil
        currentCue = nil
        coachIsReady = false
        lastServedBreak = nil
        walkBreakCounter = 0
        lastCoachPhase = nil
```

- [ ] **Step 7: Add the context builder**

Append to `FitBud Watch App/Models/CoachContext.swift`:

```swift
/// Assembles a `CoachContext` from the plan and whatever history is available.
///
/// Everything except the plan is optional: a context missing recovery data is
/// still worth sending, and blocking a run's coaching on a HealthKit read that
/// might be slow would defeat the point.
enum CoachContextBuilder {
    @MainActor
    static func build(planDay: PlanDay?, runs: [HistoricRun] = [], asOf date: Date = Date()) -> CoachContext? {
        guard let plan = try? PlanStore.loadBundled() else { return nil }
        let progress = blockProgress(plan: plan, runs: runs, asOf: date)
        let day = planDay ?? plan.day(on: date)

        let zoneTable = HRZone.table
            .map { "\($0.id) \($0.lowerBPM)-\($0.upperBPM)" }
            .joined(separator: ", ")

        let recent = runs.prefix(3).map { run in
            let pace = run.paceSecPerKm.map { "\(formatPace($0))/km" } ?? "unknown pace"
            let bpm = run.averageHeartRate.map { "avg \(Int($0))bpm" } ?? "no HR"
            let zone = run.zone.map { " (\($0.id))" } ?? ""
            return "\(TrainingPlan.dayKey(for: run.date)): \(String(format: "%.1f", run.distanceKm))km at \(pace), \(bpm)\(zone)"
        }

        return CoachContext(
            sessionTitle: day?.title ?? "Run",
            sessionNotes: day?.notes ?? "",
            targetKm: day?.targetKm ?? 5,
            targetZone: day?.zone ?? "Z2",
            runWalk: day?.runWalk.map { "run \(Int($0.runMin))min / walk \(Int($0.walkMin))min" },
            daysToRace: progress?.daysToRace ?? plan.daysToRace(from: date),
            weekIndex: progress?.weekIndex ?? 0,
            totalWeeks: progress?.totalWeeks ?? 8,
            weekFocus: progress?.weekFocus ?? "",
            weekCompletedKm: progress?.completedKm ?? 0,
            weekPlannedKm: progress?.plannedKm ?? 0,
            easyShare: progress?.easyShare,
            recentRuns: Array(recent),
            sleepHours: nil,
            restingHeartRate: nil,
            hrv: nil,
            zoneTable: zoneTable
        )
    }
}
```

Note `sleepHours`, `restingHeartRate` and `hrv` are `nil` here. Reading them needs a HealthKit query that does not exist yet, and `promptSummary` already omits absent values rather than sending zeros. Wiring real recovery data is deliberately left for a follow-up so this task stays reviewable.

- [ ] **Step 8: Run the tests**

Expected: PASS — **166 tests**.

- [ ] **Step 9: Commit both tasks together**

```bash
git add "FitBud Watch App/UI/CoachMessageView.swift" "FitBud Watch App/UI/EffortPage.swift" "FitBud Watch App/UI/WorkoutSessionModel.swift" "FitBud Watch App/Models/CoachContext.swift" "FitBud Watch AppTests/CoachEngineTests.swift"
git commit -m "feat: wire the coach into the workout session"
```

---

### Task 10: Settings and app wiring

**Files:**
- Create: `FitBud Watch App/UI/SettingsView.swift`
- Modify: `FitBud Watch App/UI/HomeView.swift`
- Modify: `FitBud Watch App/FitBudApp.swift`

**Interfaces:**
- Consumes: `CoachSettings`, `ProviderID`, `Secrets`, `WatchCoachSpeaker`
- Produces: `SettingsView(settings:)`

- [ ] **Step 1: Write the settings page**

`FitBud Watch App/UI/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    let settings: CoachSettings

    var body: some View {
        List {
            Section("Coach") {
                Toggle("Speak cues", isOn: Binding(
                    get: { settings.isSpeechEnabled },
                    set: { settings.isSpeechEnabled = $0 }
                ))
                .font(.footnote)

                Picker("Provider", selection: Binding(
                    get: { settings.providerID },
                    set: { settings.providerID = $0 }
                )) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .font(.footnote)
            }

            Section {
                // Says plainly whether coaching will actually work, rather than
                // letting the athlete discover mid-run that no key is set.
                Label(
                    Secrets.hasAnyKey ? "API key configured" : "No API key — coaching disabled",
                    systemImage: Secrets.hasAnyKey ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption2)
                .foregroundStyle(Secrets.hasAnyKey ? .green : .orange)

                if !Secrets.hasAnyKey {
                    Text("Add Secrets.plist to the app's Resources folder.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
```

- [ ] **Step 2: Link it from the home screen**

In `FitBud Watch App/UI/HomeView.swift`, add a `settings` property and a link. Add the property beside the existing `@State private var home = HomeModel()`:

```swift
    let settings: CoachSettings
```

and add the link immediately after the existing "All sessions" `NavigationLink`:

```swift
                NavigationLink("Settings") {
                    SettingsView(settings: settings)
                }
                .font(.footnote)
```

- [ ] **Step 3: Own the settings and speaker at App scope**

In `FitBud Watch App/FitBudApp.swift`, add beside the existing model:

```swift
    @State private var settings = CoachSettings()
```

and configure the coach when the scene appears, passing settings down:

```swift
            RootView(model: model, settings: settings)
                .task {
                    model.configureCoach(
                        provider: settings.makeProvider(),
                        speaker: WatchCoachSpeaker(),
                        settings: settings
                    )
                }
```

- [ ] **Step 4: Thread settings through RootView**

In `FitBud Watch App/UI/RootView.swift`, add `let settings: CoachSettings` beside the existing `let model:`, and pass it to `HomeView(model: model, settings: settings)`.

- [ ] **Step 5: Run the tests**

Expected: PASS — **166 tests**. If a test constructs `RootView` or `HomeView`, update the call site for the new parameter and say so in the report.

- [ ] **Step 6: Verify on the simulator**

Build, install, launch. Crown-scroll the home screen to Settings, open it, and confirm: the speech toggle flips and persists across a relaunch; the provider picker shows OpenAI and Gemini; and the key row reads **"No API key — coaching disabled"** in orange, because no `Secrets.plist` is bundled. That last one is the point — it must say so rather than fail silently.

**Read the screenshots.**

- [ ] **Step 7: Commit**

```bash
git add "FitBud Watch App/UI/SettingsView.swift" "FitBud Watch App/UI/HomeView.swift" "FitBud Watch App/UI/RootView.swift" "FitBud Watch App/FitBudApp.swift"
git commit -m "feat: add coach settings"
```

---

### Task 11: Post-run analysis

**Files:**
- Modify: `FitBud Watch App/UI/WorkoutSessionModel.swift`
- Modify: `FitBud Watch App/UI/SummaryView.swift`
- Modify: `FitBud Watch App/UI/RootView.swift`

**Interfaces:**
- Consumes: `AIProviding.analyze`, `CoachContextBuilder`, `WorkoutAnalysis`
- Produces: `WorkoutSessionModel.analysis: WorkoutAnalysis?`

- [ ] **Step 1: Request the analysis when a workout finishes**

In `WorkoutSessionModel`, add:

```swift
    private(set) var analysis: WorkoutAnalysis?
```

Clear it in `reset()` (`analysis = nil`), and request it at the end of `finish(_:)`:

```swift
        requestAnalysis(for: workout)
```

with:

```swift
    /// Fetched after the run is already saved and the summary already on
    /// screen. It appears if it arrives and is simply absent if it does not.
    private func requestAnalysis(for workout: CompletedWorkout) {
        guard let provider else { return }
        let planDay = (try? PlanStore.loadBundled())?.day(on: Date())
        guard let context = CoachContextBuilder.build(planDay: planDay) else { return }
        Task { [weak self] in
            guard let result = try? await provider.analyze(workout: workout, context: context) else { return }
            self?.analysis = result
        }
    }
```

- [ ] **Step 2: Show it on the summary**

Add a parameter to `SummaryView`:

```swift
    let analysis: WorkoutAnalysis?
```

and render it directly under the duration, before the zone breakdown:

```swift
                if let analysis {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analysis.summary)
                            .font(.system(size: 13, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(analysis.takeaway)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.elapsedYellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
```

- [ ] **Step 3: Pass it through RootView**

In the `.finished` case, add `analysis: model.analysis` to the `SummaryView` call.

- [ ] **Step 4: Run the tests**

Expected: PASS — **166 tests**. Update any test constructing `SummaryView` for the new parameter and say so in the report.

- [ ] **Step 5: Commit**

```bash
git add "FitBud Watch App/UI/WorkoutSessionModel.swift" "FitBud Watch App/UI/SummaryView.swift" "FitBud Watch App/UI/RootView.swift"
git commit -m "feat: show post-run analysis on the summary"
```

---

### Task 12: End-to-end verification

**Files:** no new files except a DEBUG fake provider. Fixes wherever this pass finds problems.

- [ ] **Step 1: Add a DEBUG fake provider so cues can be seen without spending money**

`FitBud Watch App/Coach/DemoAIProvider.swift`:
```swift
#if DEBUG
import Foundation

/// Returns a canned brief instantly so the coaching UI can be driven on a
/// simulator with no network and no API spend.
struct DemoAIProvider: AIProviding {
    let id: ProviderID = .openAI

    func brief(context: CoachContext) async throws -> SessionBrief {
        SessionBrief(
            opening: "Easy today. Let the walk breaks do the work.",
            rules: [
                CueRule(trigger: .zoneAbove(ceiling: "Z2", sustainedSec: 20),
                        message: "Above easy. Ease off and let it settle.",
                        urgency: .immediate, repeats: true),
                CueRule(trigger: .phaseStarted(.walk), message: "Walk break. Breathe.", repeats: true),
                CueRule(trigger: .splitCompleted(index: nil), message: "Another kilometre down.", repeats: true),
                CueRule(trigger: .halfway, message: "Halfway. Still feeling easy?")
            ]
        )
    }

    func liveCue(context: LiveCoachContext) async throws -> String {
        try? await Task.sleep(for: .milliseconds(400))
        return "Splits are steady. Keep this rhythm."
    }

    func analyze(workout: CompletedWorkout, context: CoachContext) async throws -> WorkoutAnalysis {
        WorkoutAnalysis(
            summary: "Steady run, mostly in Z2. That is exactly the assignment.",
            takeaway: "Start the next one thirty seconds slower."
        )
    }
}
#endif
```

Wire it in `FitBudApp.swift`'s `.task`, so a debug build coaches without a key:

```swift
#if DEBUG
                    let provider: (any AIProviding)? = settings.makeProvider() ?? DemoAIProvider()
#else
                    let provider = settings.makeProvider()
#endif
                    model.configureCoach(provider: provider, speaker: WatchCoachSpeaker(), settings: settings)
```

- [ ] **Step 2: Full suite and clean build**

```bash
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" test 2>&1 | grep -E "✔|✘|error:|\*\* TEST"
rm -rf build
xcodebuild -project FitBud.xcodeproj -scheme "FitBud Watch App" -destination "id=ABFC4C29-F866-4D1D-9A8F-345DFAFF82F5" -derivedDataPath build build 2>&1 | grep -E "warning:|error:|\*\* BUILD"
```
Expected: **166 tests**, `** BUILD SUCCEEDED **`, no warnings in our own code.

- [ ] **Step 3: Drive the whole thing and screenshot it**

Install, launch, start the demo run, and stay on the Effort page. The scripted heart rate sweeps 130→200 at 20×, so it crosses out of Z2 within about a minute and covers a kilometre every ~30s.

**Confirm and report each of these, with screenshots:**
- the opening line appears shortly after starting
- a drift cue fires when the sweep climbs past Z2, and **the wash behind the message is the zone colour** — that is the whole reason covering the ring is acceptable
- a split cue appears at a kilometre
- messages auto-dismiss after ~6s, and a tap dismisses immediately
- **cues do not stack or flicker** — the 90s gap is respected in practice, not just in tests
- the crown still pages away while a message is up
- text is never clipped at 46mm, and a long message shrinks rather than truncating

- [ ] **Step 4: Confirm the untouchable files are untouched**

```bash
git diff --stat 8bf16a4..HEAD -- "FitBud Watch App/Health/HealthKitWorkoutRecorder.swift" "FitBud Watch App/Health/WorkoutRecording.swift"
```
Expected: empty.

- [ ] **Step 5: Write the manual real-network smoke test**

Create `docs/AI-SMOKE-TEST.md` with the exact steps for the athlete to run once, by hand, after rotating their key:

1. Create `FitBud Watch App/Resources/Secrets.plist` from `Secrets.example.plist` and paste in the rotated key.
2. Confirm `git status` does **not** list it.
3. Build and run. Open Settings and confirm the key row reads "API key configured" in green.
4. Start a real run with the watch on the wrist and a phone nearby.
5. Confirm the opening line arrives within ~10s and is specific to today's session — it should name the session and the target zone, not generic encouragement.
6. Confirm a live cue arrives at a walk break referencing real splits.
7. End the run and confirm the summary carries an analysis.
8. Note the elapsed time between tapping Start and the opening line appearing — if it exceeds ~10s, switch the model constant to `gpt-5-nano`.

Commit it.

- [ ] **Step 6: Fix what you found, then re-run steps 2–3**

Commit fixes individually. If you found nothing, say so explicitly rather than inventing a change.

## Definition of done

- [ ] **166 tests** passing, clean build with no warnings in our own code
- [ ] With no key configured, the app records runs exactly as before and Settings says coaching is disabled
- [ ] With the demo provider, cues appear on the Effort page over the zone wash and auto-dismiss
- [ ] `HealthKitWorkoutRecorder.swift` and `WorkoutRecording.swift` untouched
- [ ] `project.pbxproj` unchanged by every commit
- [ ] `Secrets.plist` is gitignored and `git status` never lists it
- [ ] `docs/AI-SMOKE-TEST.md` written

## Out of scope

Per spec §11: plan adaptation and the mutation validator; conversation; on-device models; coaching on the other four pages. Also deferred and noted in Task 9: real sleep/RHR/HRV values in `CoachContext` — the fields exist and are omitted from the prompt when nil, so wiring a HealthKit read later changes nothing above it.
