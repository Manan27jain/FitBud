import SwiftUI

/// The screen the athlete opens the app to. Ordered by what they can act on:
/// today's session first, then why it matters, then how the week is going.
struct HomeView: View {
    let model: WorkoutSessionModel
    let settings: CoachSettings
    @State private var home = HomeModel()

    // Carried over from the `StartView` this screen replaces: it was the
    // app's only call site for `HealthAuthorization.requestPermissions()`.
    // Deleting `StartView` without this would leave a fresh install with no
    // path that ever prompts for HealthKit access — `authorizationStatus`
    // would stay `.notDetermined` forever, and every workout start would
    // fail with "not authorized" with no way for the athlete to fix it.
    @State private var authorization = HealthAuthorization()
    @State private var didRequestHealthAccess = false
    @State private var authorizationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let loadError = home.loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let message = model.errorMessage ?? authorizationMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                todayCard
                countdownCard
                weekCard
                easyCard
                recentCard

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

                NavigationLink("Settings") {
                    SettingsView(settings: settings)
                }
                .font(.footnote)

                NavigationLink("Health history probe") {
                    HistoryProbeView()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

#if DEBUG
                Button("Demo run (scripted HR)") {
                    Task { await model.startDemo() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
#endif
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("FitBud")
        .task { await home.load() }
        .task { await requestHealthAccessIfNeeded() }
    }

    private func requestHealthAccessIfNeeded() async {
        guard !didRequestHealthAccess else { return }
        didRequestHealthAccess = true
        do {
            try await authorization.requestPermissions()
        } catch {
            authorizationMessage = "Health access failed: \(error.localizedDescription)"
        }
    }

    // MARK: Today

    @ViewBuilder private var todayCard: some View {
        if let today = home.today {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY · \(today.dow.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(today.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                if today.isRunningSession {
                    Text(sessionDetail(today))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await model.start(WorkoutConfiguration(planDay: today)) }
                    } label: {
                        Label("Start", systemImage: "figure.run")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(zoneColor(today.zone))
                    .padding(.top, 2)
                } else {
                    Text(today.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("NO SESSION TODAY")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Outside the training block")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
    }

    private func sessionDetail(_ day: PlanDay) -> String {
        var parts: [String] = []
        if day.targetKm > 0 {
            parts.append(String(format: "%.0f km", day.targetKm))
        }
        if let zone = day.zone, let hrZone = HRZone.table.first(where: { $0.id == zone }) {
            parts.append("\(zone) \(hrZone.lowerBPM)–\(hrZone.upperBPM) bpm")
        }
        if let runWalk = day.runWalk {
            parts.append("run \(Int(runWalk.runMin))′/walk \(Int(runWalk.walkMin))′")
        }
        return parts.joined(separator: " · ")
    }

    private func zoneColor(_ id: String?) -> Color {
        HRZone.table.first { $0.id == id }?.color ?? .green
    }

    // MARK: Countdown

    @ViewBuilder private var countdownCard: some View {
        if let progress = home.progress {
            VStack(alignment: .leading, spacing: -1) {
                Text("\(progress.daysToRace)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.elapsedYellow)
                Text("DAYS TO THE HALF")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Week \(progress.weekIndex) of \(progress.totalWeeks)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: This week

    @ViewBuilder private var weekCard: some View {
        if let progress = home.progress {
            VStack(alignment: .leading, spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", progress.completedKm))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(String(format: "%.0f", progress.plannedKm)) KM")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text("\(progress.completedSessions)/\(progress.plannedSessions)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                ProgressTrack(fraction: progress.volumeFraction)

                Text(progress.weekFocus)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Easy running

    @ViewBuilder private var easyCard: some View {
        if let progress = home.progress, let easyShare = progress.easyShare {
            let onTarget = easyShare >= 0.8
            VStack(alignment: .leading, spacing: 4) {
                Text("EASY RUNNING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int((easyShare * 100).rounded()))%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(onTarget ? .green : .orange)
                    Text("OF RUNS · TARGET 80%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressTrack(fraction: easyShare, color: onTarget ? .green : .orange)

                // The plan's single most important rule, so it says out loud
                // what to do rather than leaving a number to be interpreted.
                Text(onTarget
                     ? "On target. Keep the easy runs easy."
                     : "Too hard. Slow down and let the walk breaks work.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Recent runs

    @ViewBuilder private var recentCard: some View {
        if !home.recentRuns.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("RECENT RUNS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(home.recentRuns.prefix(4)) { run in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(run.zone?.color ?? .gray.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(run.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f km", run.distanceKm))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Spacer(minLength: 0)
                        Text(run.paceSecPerKm.map { "\(formatPace($0))/km" } ?? "--")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
