#if DEBUG
import AnamnesisKit
import SwiftData
import SwiftUI

// SPIKE: spec 012 AC1 — seeds made-up poems (never real ones) and times the Library search on the device.
struct LibrarySamplesView: View {
    static let marker = "DEBUG sample"
    private static let words = ["river", "lantern", "salt", "orchard", "quiet", "ember", "harbor", "winter",
                                "thread", "meadow", "glass", "hollow", "sparrow", "copper", "tide", "linen"]

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.modelContext) private var context
    @State private var word = "ember"
    @State private var result: String?
    @State private var sampleCount = 0

    var body: some View {
        List {
            Section {
                LabeledContent("Sample poems", value: "\(sampleCount)")
                Button("Add 200 sample poems", systemImage: "plus") { run { try addSamples() } }
                Button("Remove sample poems", systemImage: "trash", role: .destructive) { run { try removeSamples() } }
            } footer: {
                Text("Generated from a word list and marked \"\(Self.marker)\" in the source field.")
            }
            Section("Time search (AC1 < 200 ms)") {
                TextField("Word", text: $word).textInputAutocapitalization(.never)
                Button("Run search", systemImage: "stopwatch") { Task { await timeSearch() } }
                if let result { Text(result).font(.callout.monospacedDigit()) }
            }
        }
        .navigationTitle("Library samples")
        .onAppear(perform: countSamples)
    }

    private func addSamples() throws {
        var generator = SystemRandomNumberGenerator()
        for index in 0..<200 {
            let lines = (0..<8).map { _ in
                (0..<5).map { _ in Self.words.randomElement(using: &generator) ?? "" }.joined(separator: " ")
            }
            let poem = Poem(body: lines.prefix(4).joined(separator: "\n") + "\n\n"
                            + lines.suffix(4).joined(separator: "\n"))
            poem.title = index % 2 == 0 ? "Sample \(index)" : nil
            poem.poet = index % 4 == 0 ? "Sample Poet \(index % 12)" : nil
            poem.sourceNote = Self.marker
            context.insert(poem)
        }
        try context.save()
    }

    private func removeSamples() throws {
        let marker = Self.marker
        try context.delete(model: Poem.self, where: #Predicate { $0.sourceNote == marker })
        try context.save()
    }

    /// The Library's own predicate on a fresh context, off the main actor.
    private func timeSearch() async {
        let container = environment.library.container
        let filter = LibraryFilter(searchText: word)
        let outcome = await Task.detached {
            let context = ModelContext(container)
            var count = 0
            let elapsed = try ContinuousClock().measure {
                count = filter.refine(try context.fetch(FetchDescriptor<Poem>(predicate: filter.predicate))).count
            }
            let total = try context.fetchCount(FetchDescriptor<Poem>())
            return (count, total, elapsed)
        }.result
        switch outcome {
        case .success(let (count, total, elapsed)):
            let millis = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
            result = String(format: "%d of %d poems match · %.1f ms", count, total, millis)
            // The searched word is not logged: logs never hold poem text (spec 014 R3).
            environment.log(.ui).notice("library search timing matches=\(count) total=\(total) ms=\(millis)")
        case .failure(let error):
            result = "Search failed: \(error.localizedDescription)"
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            result = nil
        } catch {
            context.rollback()
            result = "Failed: \(error.localizedDescription)"
        }
        countSamples()
    }

    private func countSamples() {
        let marker = Self.marker
        let samples = FetchDescriptor<Poem>(predicate: #Predicate { $0.sourceNote == marker })
        sampleCount = (try? context.fetchCount(samples)) ?? 0
    }
}
#endif
