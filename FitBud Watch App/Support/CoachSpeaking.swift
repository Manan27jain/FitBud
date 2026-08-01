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
