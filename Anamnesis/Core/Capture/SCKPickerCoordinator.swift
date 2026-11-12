#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

// SPIKE: owns the `SCContentSharingPicker` observer registration. Observer callbacks may arrive on any queue;
// they hop to the main actor before reaching the backend.
final class SCKPickerCoordinator: NSObject, SCContentSharingPickerObserver {
    enum Style: String, CaseIterable, Identifiable {
        case systemDefault = "present()"
        case display = ".display"
        case window = ".window"
        var id: String { rawValue }
    }

    enum Outcome {
        case filter(SCContentFilter, forExistingStream: Bool)
        case cancelled
        case failed(String)
    }

    var onOutcome: ((Outcome) -> Void)?
    /// Short identity for the log: two coordinators would both receive every selection (F-032, H1).
    let id = String(UUID().uuidString.prefix(4))
    private let picker = SCContentSharingPicker.shared
    private var isRegistered = false

    var isAvailable: Bool { picker.isAvailable }

    /// Registers the observer and hides mic/camera controls: we capture app audio only (CLAUDE.md mission).
    /// `isActive` is set per presentation instead (F-032, H2): a picker left active forever stopped presenting
    /// from the background after its first use.
    func activate() {
        guard !isRegistered else { return }
        var configuration = picker.defaultConfiguration
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        isRegistered = true
    }

    /// Ends a presentation cycle: after a cancel or failure, and when the stream it produced stops.
    func endPresentation() {
        picker.isActive = false
    }

    func deactivate() {
        guard isRegistered else { return }
        picker.isActive = false
        picker.remove(self)
        isRegistered = false
    }

    /// `settle`: wait between activating and presenting (H3: presenting milliseconds after activation failed on
    /// a cold launch).
    func present(_ style: Style, settle: Duration = .zero) {
        picker.isActive = true
        guard settle > .zero else { return show(style) }
        Task {
            try? await Task.sleep(for: settle)
            show(style)
        }
    }

    private func show(_ style: Style) {
        switch style {
        case .systemDefault: picker.present()
        case .display: picker.present(using: .display)
        case .window: picker.present(using: .window)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?
    ) {
        let existing = stream != nil
        let box = FilterBox(filter: filter)
        Task { @MainActor in self.onOutcome?(.filter(box.filter, forExistingStream: existing)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.onOutcome?(.cancelled) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        let error = error as NSError
        let message = "\(error.domain) \(error.code): \(error.localizedDescription)"
        Task { @MainActor in self.onOutcome?(.failed(message)) }
    }
}
/// `SCContentFilter` is not Sendable, but SCK hands us a filter it no longer mutates (its properties are
/// read-only), and after the hop only the main actor touches it — so moving it across is safe.
private nonisolated struct FilterBox: @unchecked Sendable {
    let filter: SCContentFilter
}
#endif
