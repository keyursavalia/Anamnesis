#if DEBUG
import AVFAudio
import Foundation
import Observation

// SPIKE: listen-back for spool segments (spec 002 §4.3, DEVICE_TEST_PROTOCOLS §7). The Lab disables playback
// while capturing: our own output would be excluded from capture but could still confuse the operator.
@Observable
final class SegmentPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playingURL: URL?
    private(set) var lastError: String?
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        do {
            // `.playback` only while previewing, so the iPad's speaker plays it regardless of other settings.
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            self.player = player
            playingURL = url
            lastError = nil
        } catch {
            lastError = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func stop() {
        player?.stop()
        player = nil
        guard playingURL != nil else { return }
        playingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
#endif
