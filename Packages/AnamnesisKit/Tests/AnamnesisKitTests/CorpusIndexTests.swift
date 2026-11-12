import Testing
@testable import AnamnesisKit

@Suite("CorpusIndex")
struct CorpusIndexTests {
    typealias File = CorpusIndex.File

    @Test("pairs clips with truth and metadata")
    func pairs() {
        let (clips, issues) = CorpusIndex.build(
            clipFiles: [File(name: "a1.m4a", size: 10), File(name: "m1.MP4", size: 10)],
            truthFiles: [File(name: "a1.txt", size: 5), File(name: "m1.txt", size: 0)],
            metaCSV: "clip,category,language,notes\na1.m4a,a,en,\"soft, slow\"\nm1,M,,music only\n")
        #expect(clips == [
            CorpusClip(id: "a1", clipFile: "a1.m4a", truthFile: "a1.txt", category: "A", language: "en",
                       notes: "soft, slow"),
            CorpusClip(id: "m1", clipFile: "m1.MP4", truthFile: "m1.txt", category: "M", notes: "music only")
        ])
        #expect(issues.isEmpty) // an empty truth is valid for category M
    }

    @Test("reports every validation problem")
    func validation() {
        let (clips, issues) = CorpusIndex.build(
            clipFiles: [File(name: "a.m4a", size: 1), File(name: "a.wav", size: 1), File(name: "b.mp3", size: 1),
                        File(name: "c.caf", size: 0), File(name: "d.mov", size: 1), File(name: ".DS_Store", size: 1)],
            truthFiles: [File(name: "a.txt", size: 0), File(name: "z.txt", size: 3)],
            metaCSV: "clip,category\n,\nghost,A\n")
        #expect(clips.map(\.id) == ["a", "d"])
        #expect(issues == [
            CorpusIssue(file: "meta.csv line 2", problem: .badMetaRow),
            CorpusIssue(file: "a.txt", problem: .emptyFile),
            CorpusIssue(file: "a.wav", problem: .duplicateClip),
            CorpusIssue(file: "b.mp3", problem: .unsupportedFormat),
            CorpusIssue(file: "c.caf", problem: .emptyFile),
            CorpusIssue(file: "d.mov", problem: .missingTruth),
            CorpusIssue(file: "z.txt", problem: .truthWithoutClip),
            CorpusIssue(file: "meta.csv: ghost", problem: .unknownMetaClip)
        ])
    }

    @Test("CSV fields handle quotes, commas and empty cells")
    func csvFields() {
        #expect(CorpusIndex.csvFields("a,\"b, c\",\"say \"\"hi\"\"\",") == ["a", "b, c", "say \"hi\"", ""])
        #expect(CorpusIndex.csvFields("") == [""])
    }

    @Test("works without meta.csv")
    func noMeta() {
        let (clips, issues) = CorpusIndex.build(clipFiles: [File(name: "x.wav", size: 1)],
                                                truthFiles: [File(name: "x.txt", size: 1)], metaCSV: nil)
        #expect(clips.first?.category == nil)
        #expect(issues.isEmpty)
    }
}
