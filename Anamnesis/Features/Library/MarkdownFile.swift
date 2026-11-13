import CoreTransferable
import UniformTypeIdentifiers

/// A Markdown file for the share sheet, built from text on demand (spec 014 R1).
struct MarkdownFile: Transferable {
    let text: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .markdown) { Data($0.text.utf8) }
            .suggestedFileName { $0.fileName }
    }
}
