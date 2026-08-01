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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var canBeHeard: Bool {
        #if targetEnvironment(simulator)
        // The simulator's "speaker" is the Mac's — exactly where a developer
        // wants to hear it. Real-device behaviour below is unchanged.
        return true
        #else
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .headphones:
                true
            default:
                false
            }
        }
        #endif
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

extension WatchCoachSpeaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deactivateSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deactivateSessionIfIdle()
    }

    /// A cue that replaces another mid-utterance cancels the old one after the
    /// new one has already started speaking, so this only deactivates when
    /// nothing is speaking — never pulling the session out from under fresh
    /// speech.
    private func deactivateSessionIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

/// Used in tests and previews.
struct SilentCoachSpeaker: CoachSpeaking {
    var canBeHeard: Bool { false }
    func speak(_ text: String) {}
    func stop() {}
}
