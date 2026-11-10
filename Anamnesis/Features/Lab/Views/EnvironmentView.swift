#if DEBUG
import SwiftUI

// SPIKE: Lab → Environment (spec 000 R7).
struct EnvironmentView: View {
    @State private var model = EnvironmentViewModel()

    var body: some View {
        content
            .navigationTitle("Environment")
            .toolbar { toolbar }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Probing device…")
        case .failed(let message):
            ContentUnavailableView("Report failed", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded(let report, _):
            EnvironmentReportList(report: report)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if case .loaded(_, let exportURL) = model.state {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy report", systemImage: "doc.on.doc") { model.copyReport() }
                ShareLink(item: exportURL) {
                    Label("Export report", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

private struct EnvironmentReportList: View {
    let report: DeviceEnvironmentReport

    var body: some View {
        List {
            Section("Device") {
                row("Model", report.device.modelIdentifier)
                row("iOS", "\(report.device.osVersion) (\(report.device.osBuild))")
                row("Thermal state", report.device.thermalState)
                row("Low Power Mode", report.device.lowPowerModeEnabled ? "on" : "off")
                row("Memory", report.device.physicalMemoryBytes.formatted(.byteCount(style: .memory)))
            }
            Section("App") {
                row("Bundle ID", report.app.bundleID)
                row("Version", "\(report.app.version) (\(report.app.build))")
                row("Locale", report.locale.current)
            }
            Section("Screen capture") {
                let available = report.capabilities.screenCapturePickerAvailable
                row("Picker available", available.map(yesNo) ?? "n/a (no ScreenCaptureKit in SDK)")
            }
            speechSection
        }
    }

    @ViewBuilder
    private var speechSection: some View {
        let speech = report.capabilities
        Section("Speech") {
            row("Transcriber available", yesNo(speech.speechTranscriberAvailable))
            row("Supported locales", "\(speech.supportedLocaleCount)")
            row("Sample", speech.supportedLocalesSample.joined(separator: ", "))
            let installed = speech.installedLocales
            row("Installed locales", installed.isEmpty ? "none" : installed.joined(separator: ", "))
            row("Transcriber locale", speech.transcriberLocale ?? "current locale unsupported")
            row("Asset status", speech.assetStatus ?? "n/a")
            if let format = speech.bestAudioFormat {
                row("Best format", "\(Int(format.sampleRate)) Hz · \(format.channelCount) ch · \(format.commonFormat)"
                    + (format.isInterleaved ? " · interleaved" : ""))
            } else {
                row("Best format", "n/a")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .textSelection(.enabled)
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}

#Preview {
    NavigationStack { EnvironmentView() }
}
#endif
