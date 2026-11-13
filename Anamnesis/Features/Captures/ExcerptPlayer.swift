import AnamnesisKit
import AVFAudio
import Foundation
import Observation

/// Plays a Moment from the spool while its audio still exists (spec 008 R5, R7). Plays within the one segment file
/// the Moment starts in, so an excerpt that crosses a 60-s boundary stops at the end of that file.
@Observable
final class ExcerptPlayer: NSObject, AVAudioPlayerDelegate {
    struct Excerpt: Equatable {
        let url: URL
        let offsetSec: Double
        let durationSec: Double

        init?(startSec: Double, endSec: Double, summary: SpoolSessionSummary) {
            guard let manifest = summary.manifest,
                  let segment = manifest.segments.last(where: { $0.startOffsetSec <= startSec }) else {
                return nil
            }
            url = summary.session.directory.appending(path: segment.fileName)
            offsetSec = max(0, startSec - segment.startOffsetSec)
            durationSec = max(0, endSec - startSec)
        }
    }

    private(set) var playing: Excerpt?
    private(set) var lastError: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func toggle(_ excerpt: Excerpt) {
        if playing == excerpt {
            stop()
            return
        }
        stop()
        do {
            // `.playback` only while playing, so the speaker plays it regardless of the silent switch.
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: excerpt.url)
            player.delegate = self
            player.currentTime = excerpt.offsetSec
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            self.player = player
            playing = excerpt
            lastError = nil
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(excerpt.durationSec))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            lastError = "Cannot play the excerpt: \(error.localizedDescription)"
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        guard playing != nil else { return }
        playing = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
