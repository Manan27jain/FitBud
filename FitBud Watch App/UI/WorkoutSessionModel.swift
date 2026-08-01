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
    /// Zone time from the finished workout. `state` is cleared by `reset()`, but
    /// the summary still needs this after the run has ended.
    private(set) var finishedTimeInZone: [String: TimeInterval] = [:]

    private(set) var currentCue: Cue?
    /// True once a brief — real or default — is loaded and cues can fire.
    private(set) var coachIsReady = false
    private(set) var analysis: WorkoutAnalysis?

    private var recorder: WorkoutRecording
    /// The recorder this model was configured with — the real one in
    /// production, a test double under test. `startDemo()` swaps `recorder`
    /// for a scripted one that never touches HealthKit; `reset()` restores it
    /// from here so a debug session's demo run can't silently leave every
    /// later *real* session on the fake recorder for the rest of the launch.
    /// A no-op wherever `recorder` was never swapped away from this.
    private let configuredRecorder: WorkoutRecording
    private let haptics: HapticPlaying
    private var engine: WorkoutEngine?
    private var pumpTask: Task<Void, Never>?
    private var isStarting = false
    private var isEnding = false

    private var coachEngine: CoachEngine?
    private var provider: (any AIProviding)?
    /// The provider this model was configured with — the real one (or `nil`
    /// with no key configured) in production. `startDemo()` swaps `provider`
    /// for `DemoAIProvider` so a demo run never spends a real API call even
    /// when a key is configured; `reset()` restores it from here for the same
    /// reason `configuredRecorder` exists — so a debug demo run can't leave
    /// every later *real* session on the fake provider for the rest of the
    /// launch. A no-op wherever `provider` was never swapped away from this.
    private var configuredProvider: (any AIProviding)?
    private var speaker: (any CoachSpeaking)?
    private var settings: CoachSettings?
    private var liveCueTask: Task<Void, Never>?
    private var lastServedBreak: Int?
    private var dismissTask: Task<Void, Never>?
    private var briefTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    /// Bumped on every successful `start(_:)`. Captured by `loadBrief`'s
    /// background task so a brief fetched for an earlier workout can tell,
    /// on resume, that it no longer belongs — `phase == .running` alone
    /// can't distinguish "still my workout" from "a different workout that
    /// also happens to be running."
    private var workoutGeneration = 0
    /// Elapsed time (in the current workout) at which the last cue was
    /// shown. Lets the brief's opening line defer to the rate limit instead
    /// of bypassing it.
    private var lastPresentedAt: TimeInterval?
    /// Incremented on each transition into a walk phase, so "one live call per
    /// break" holds for any run/walk ratio.
    private var walkBreakCounter = 0
    private var lastCoachPhase: RunWalkPhase?

    // `recorder` can't default directly to `HealthKitWorkoutRecorder()`: default
    // argument expressions are type-checked outside the initializer's own
    // main-actor isolation, so a default value calling a `@MainActor`-isolated
    // initializer doesn't compile even though every caller of this `init` is
    // already on the main actor. Defaulting to `nil` and constructing inside
    // the (actor-isolated) init body sidesteps that without changing behavior.
    init(recorder: WorkoutRecording? = nil, haptics: HapticPlaying = WatchHaptics()) {
        let recorder = recorder ?? HealthKitWorkoutRecorder()
        self.recorder = recorder
        self.configuredRecorder = recorder
        self.haptics = haptics
    }

    /// Injected once at app start. Kept separate from `init` so tests can
    /// construct a model without a coach at all.
    func configureCoach(provider: (any AIProviding)?, speaker: any CoachSpeaking, settings: CoachSettings) {
        self.provider = provider
        self.configuredProvider = provider
        self.speaker = speaker
        self.settings = settings
    }

    /// Shows a cue, buzzes, and speaks it when speech is on and something is
    /// paired to hear it.
    func present(_ cue: Cue) {
        currentCue = cue
        lastPresentedAt = state.elapsed
        haptics.play(.coachCue)
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

    func start(_ configuration: WorkoutConfiguration) async {
        // The same defect `end()` guards against, at the other end of the run.
        // `recorder.start(_:)` suspends for 1–3s while `beginCollection` runs
        // and `phase` stays `.idle` throughout, so the Start button is still
        // live and a second tap re-enters here. The recorder's own `start`
        // opens with `teardown()`, which nils its session; the second call
        // then builds a fresh `HKWorkoutSession` and the first, resuming
        // later, overwrites it with its own. One session is left orphaned
        // with nothing able to end it — and watchOS permits only one active
        // session, so the *next* start hangs forever. Wedged at the start
        // line, which is the worst possible moment.
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // A previous attempt's error text and metrics must not bleed into this
        // workout: otherwise a failed start leaves "Couldn't start: …" on screen
        // for the whole of the successful run that follows it.
        pumpTask?.cancel()
        pumpTask = nil
        errorMessage = nil
        state = WorkoutState()
        engine = WorkoutEngine(
            timeline: SegmentTimeline(segments: configuration.segments),
            runWalk: configuration.runWalk
        )
        do {
            // The stream belongs to this workout, so a failed start can never
            // hand a finished stream to the next one.
            let metrics = try await recorder.start(configuration)
            phase = .running
            workoutGeneration += 1
            pump(metrics)
            loadBrief(for: configuration)
        } catch {
            engine = nil
            errorMessage = "Couldn't start: \(error.localizedDescription)"
        }
    }

    /// Fetches the session brief in the background. The run has already
    /// started by the time this is called — coaching is never on the critical
    /// path, and a failure falls back to the default bundle rather than
    /// leaving the athlete uncoached.
    private func loadBrief(for configuration: WorkoutConfiguration) {
        // Any brief still in flight belonged to a workout `reset()` has since
        // torn down; it must not go on to install itself into this one.
        briefTask?.cancel()

        let planDay = (try? PlanStore.loadBundled())?.day(on: Date())
        let fallback = defaultBrief(for: planDay)
        let targetKm = planDay?.targetKm ?? 5

        coachEngine = CoachEngine(brief: fallback, targetDistanceKm: targetKm)
        coachIsReady = true

        guard let provider, let context = CoachContextBuilder.build(planDay: planDay) else { return }
        let generation = workoutGeneration
        briefTask = Task { [weak self] in
            guard let brief = try? await provider.brief(context: context) else { return }
            // `reset()` cancels this task, but cancellation of the `await`
            // above isn't guaranteed to interrupt a real network call
            // promptly. The generation check is what actually holds: a brief
            // whose workout has since ended and been replaced by a new one —
            // which `phase == .running` alone can't tell apart, since the
            // new workout is running too — is rejected here regardless of
            // whether the `Task` itself was ever torn down in time.
            guard let self, self.workoutGeneration == generation,
                  self.phase == .running || self.phase == .paused else { return }
            self.coachEngine = CoachEngine(brief: brief, targetDistanceKm: targetKm)
            // A fresh `CoachEngine` starts with no `lastDeliveredAt`, so
            // presenting the opening unconditionally would skip the rate
            // limit it exists to enforce. If a cue already landed inside the
            // floor — an immediate drift warning from the default bundle is
            // the realistic case — the opening is no longer a "starting now"
            // message; skip it rather than double up.
            let recentlyPresented = self.lastPresentedAt.map {
                self.state.elapsed - $0 < CoachEngine.urgentFloor
            } ?? false
            if !brief.opening.isEmpty, !recentlyPresented {
                self.present(Cue(id: UUID(), message: brief.opening, urgency: .atNextBreak, firedAt: 0))
            }
        }
    }

#if DEBUG
    /// Starts a scripted workout against `DemoWorkoutRecorder` so the UI can be
    /// seen on a simulator, which has no heart-rate sensor. Debug builds only.
    ///
    /// Also swaps in `DemoAIProvider`, mirroring the recorder swap above: a
    /// real key may well be configured on the machine running this, and
    /// without the swap `provider` would still be the live `OpenAIProvider`,
    /// so every demo run would silently spend real API calls. `reset()`
    /// restores both from their configured originals.
    func startDemo() async {
        recorder = DemoWorkoutRecorder()
        provider = DemoAIProvider()
        await start(.longRun5to1)
    }
#endif

    private func pump(_ metrics: AsyncThrowingStream<LiveMetrics, Error>) {
        // This `Task` inherits `@MainActor` from the enclosing type, so the
        // property accesses below need no `await` and no extra hopping.
        pumpTask = Task { [weak self] in
            do {
                for try await sample in metrics {
                    guard let self else { return }
                    guard var engine = self.engine else { continue }
                    let events = engine.ingest(sample)
                    self.apply(engine: engine, events: events)
                }
            } catch {
                // The stream only throws when the recorder's underlying
                // session fails on its own (see `HealthKitWorkoutRecorder`'s
                // `didFailWithError`); a normal `end()` finishes it without
                // an error. That makes this catch block the model's only
                // signal that the session died mid-workout, so route to the
                // same recoverable summary a failed `end()` produces instead
                // of leaving the live screen frozen on its last values.
                guard let self else { return }
                self.errorMessage = "Workout session failed: \(error.localizedDescription)"
                self.finish(self.unsavedWorkout())
            }
        }
    }

    private func apply(engine: WorkoutEngine, events: [WorkoutEvent]) {
        self.engine = engine
        state = engine.state
        for event in events {
            haptics.play(haptic(for: event))
        }
        evaluateCoach(events: events)
    }

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

    func pause() async {
        do {
            try await recorder.pause()
            phase = .paused
        } catch {
            errorMessage = "Couldn't pause: \(error.localizedDescription)"
        }
    }

    func resume() async {
        do {
            try await recorder.resume()
            phase = .running
        } catch {
            errorMessage = "Couldn't resume: \(error.localizedDescription)"
        }
    }

    func end() async {
        // `end()` suspends for as long as HealthKit takes to save, and the End
        // button stays tappable throughout. A second tap — trivially easy with
        // cold hands — used to re-enter here, call `session.end()` on a session
        // the first call had already ended, and replace a perfectly good saved
        // summary with "Couldn't save to Health". Observed on the simulator.
        guard !isEnding else { return }
        isEnding = true
        defer { isEnding = false }

        // `recorder.end(splits:)` needs the splits array as an argument, and
        // it only finishes the `metrics` stream (via `continuation.finish()`)
        // *inside* that call — after the splits have already been handed
        // over. So we can't call it first and read a post-drain `state.splits`
        // afterwards; that would be circular. Instead we give `pump()`'s
        // `for await` loop a chance to run before we snapshot splits: if
        // HealthKit already delivered a final `LiveMetrics` sample that would
        // complete the last kilometre split, it is sitting in the stream's
        // buffer, and `AsyncStream` resumes a suspended `for await` as soon as
        // a value is available — without an extra suspension per element — so
        // one `Task.yield()` is enough to let the pump loop drain the current
        // backlog and update `state.splits` before we cancel it. Cancelling
        // first (the previous behavior) risked dropping that sample entirely.
        await Task.yield()
        pumpTask?.cancel()
        pumpTask = nil

        let splits = state.splits
        do {
            let workout = try await recorder.end(splits: splits)
            // A stale message from an earlier pause/resume failure (or a
            // session failure the pump loop already recorded) must not
            // render under a summary that in fact saved successfully —
            // `SummaryView` treats any non-nil `errorMessage` as "this run
            // wasn't saved".
            errorMessage = nil
            finish(workout)
        } catch {
            // Losing the HealthKit save is bad; being trapped on a frozen live
            // screen after a two-hour run is worse. The recorder has already
            // torn its session down, so retrying cannot succeed — go to the
            // summary anyway, built from the state we accumulated live, and say
            // plainly that it wasn't saved. The athlete can read their run and
            // leave.
            errorMessage = "Couldn't save to Health: \(error.localizedDescription)"
            finish(unsavedWorkout())
        }
    }

    /// Fetched after the run is already saved and the summary already on
    /// screen. It appears if it arrives and is simply absent if it does not.
    private func requestAnalysis(for workout: CompletedWorkout) {
        guard let provider else { return }
        let planDay = (try? PlanStore.loadBundled())?.day(on: Date())
        guard let context = CoachContextBuilder.build(planDay: planDay) else { return }
        // Cancel any analysis still in flight from a previous workout, so a
        // stale analysis can't land on the current one's summary.
        analysisTask?.cancel()
        let generation = workoutGeneration
        analysisTask = Task { [weak self] in
            guard let result = try? await provider.analyze(workout: workout, context: context) else { return }
            // Only apply this analysis if we're still on the same workout
            // generation. If the athlete started a new run while this was in
            // flight, reject it rather than contaminating the new run's summary.
            guard let self, self.workoutGeneration == generation else { return }
            self.analysis = result
        }
    }

    /// The one door into `.finished`, used by a successful `end()`, a failed
    /// `end()`, and `pump()`'s catch block (the session dying on its own).
    /// Three call sites used to each assign `finishedTimeInZone` themselves;
    /// one of them — the session-failure path — didn't, so an athlete whose
    /// watch dropped the session mid-run got a summary with an empty zone
    /// breakdown despite `state.timeInZone` being full of real data. Funneling
    /// every route through here means there is exactly one place responsible
    /// for capturing it, not three to keep in sync.
    private func finish(_ workout: CompletedWorkout) {
        finishedTimeInZone = state.timeInZone
        phase = .finished(workout)
        requestAnalysis(for: workout)
    }

    /// Reconstructs a summary from live state when HealthKit refuses to hand one
    /// back. `state.elapsed` excludes paused time, matching a real
    /// `CompletedWorkout.duration`; the heart rate is the last sample seen
    /// rather than a true average, which is the best available here.
    private func unsavedWorkout() -> CompletedWorkout {
        let end = Date()
        return CompletedWorkout(
            start: end.addingTimeInterval(-state.elapsed),
            end: end,
            duration: state.elapsed,
            distanceMeters: state.distanceMeters,
            activeEnergyKcal: state.activeEnergyKcal,
            averageHeartRate: state.heartRate,
            splits: state.splits
        )
    }

    /// Returns to the start screen so a second workout can be recorded without
    /// force-quitting the app.
    func reset() {
        pumpTask?.cancel()
        pumpTask = nil
        engine = nil
        state = WorkoutState()
        errorMessage = nil
        finishedTimeInZone = [:]
        analysis = nil
        phase = .idle
        recorder = configuredRecorder
        provider = configuredProvider
        liveCueTask?.cancel()
        liveCueTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        briefTask?.cancel()
        briefTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        coachEngine = nil
        currentCue = nil
        coachIsReady = false
        lastServedBreak = nil
        lastPresentedAt = nil
        walkBreakCounter = 0
        lastCoachPhase = nil
    }
}
