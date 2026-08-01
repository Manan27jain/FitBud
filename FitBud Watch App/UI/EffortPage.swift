import SwiftUI

/// Page 1, the default. Heart rate and zone at a glance, with the run/walk
/// interval draining around them.
struct EffortPage: View {
    let model: WorkoutSessionModel

    private var state: WorkoutState { model.state }

    /// The zone *name*, which is what spec §4 asks for beneath the heart rate
    /// — not the id as well. "Z4 THRESHOLD" was 97pt wide against a clear
    /// chord of about 82pt at this height inside the ring, so its leading "Z"
    /// was swallowed by the phase ring's start cap, in the ring's own colour:
    /// it read as "4 THRESHOLD". The id is redundant here anyway — the lit
    /// scale segment and the needle already say which rung this is, and
    /// "THRESHOLD" is the part that means something at a glance.
    ///
    /// "NO ZONE" only when there's no heart-rate sample at all — genuinely
    /// no signal. Once a sample arrives but sits below Z1's floor (resting
    /// or early in a run), that's "WARMING UP", not absent: `currentZone`
    /// stays correctly `nil` from `HRZone.zone(for:)`, but the label and
    /// tint should read as alive rather than broken.
    private var zoneLabelText: String {
        if let zone = state.currentZone { return zone.name.uppercased() }
        return state.heartRate != nil ? "WARMING UP" : "NO ZONE"
    }

    private var zoneLabelColor: Color {
        if let zone = state.currentZone { return zone.color }
        return state.heartRate != nil ? EffortRingView.warmingUpTint : .secondary
    }

    /// The page wash tracks the live zone, which is the whole point of it: the
    /// screen warms from green through orange to red as the athlete drifts out
    /// of Z2, so drift is visible from the corner of an eye without any number
    /// being read. 80% of this athlete's running has to sit in Z1–Z2 and every
    /// run in his history was at 85–92% of max, so this is the feature, not
    /// decoration. Same three-way split as the zone label above it: a real
    /// zone, warming up, or genuinely no signal.
    private var washTint: Color {
        if let zone = state.currentZone { return zone.color }
        return state.heartRate != nil ? EffortRingView.warmingUpTint : Theme.noSignalTint
    }

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
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    // A box big enough for three digits, claimed before the
                    // first sample lands. "--" is narrower than "148", so
                    // without this the hero — and the zone label and countdown
                    // stacked under it — re-centre themselves the moment the
                    // heart rate arrives, 5–15 seconds into every single run.
                    .frame(width: 100, height: 50)

                Text(zoneLabelText)
                    .font(Theme.captionFont)
                    .foregroundStyle(zoneLabelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // The clear chord inside the ring at this height, measured
                    // off a 46mm screenshot: the phase ring's caps sit at the
                    // lower left and lower right and eat anything wider. The
                    // longest label ("WARMING UP") comes in just under it, so
                    // the scale factor is a guard rather than something that
                    // normally fires.
                    .frame(width: 80)

                if let phase = state.runWalkPhase, let remaining = state.phaseRemaining {
                    Text("\(phase == .run ? "RUN" : "WALK") \(formatPace(remaining))")
                        .font(Theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            // The wash below crossfades over 0.6s, which is right for a
            // background but ruinous for the numbers sitting on it: an
            // implicit animation covers everything it wraps, so the heart
            // rate ghosted its previous value every second and the zone name
            // dissolved through its old one. Digits must change crisply.
            .transaction { $0.animation = nil }

            if let cue = model.currentCue {
                CoachMessageView(message: cue.message) {
                    model.dismissCue()
                }
            }
        }
        .containerBackground(Theme.pageWash(washTint), for: .tabView)
        .animation(.easeInOut(duration: 0.6), value: state.currentZone)
        .animation(.easeInOut(duration: 0.25), value: model.currentCue)
        .navigationTitle("Effort")
    }
}
