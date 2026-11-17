#if DEBUG
import AnamnesisKit
import Foundation
import SwiftData

// SPIKE: App Store screenshots (docs/APP_STORE_SUBMISSION.md B4). Public-domain texts only, plus one note in our own
// words; never copyrighted poems or speeches. Seeded transcripts carry `marker` as their session id, which the
// Library never shows, so their titles, speakers and source links look like a real user's.
enum ScreenshotSeed {
    static let marker = "screenshot-seed"

    struct Entry {
        let title: String
        let speaker: String?
        let source: String?
        /// Age in hours: the Library sorts newest first, so this sets the order on screen.
        let hoursAgo: Double
        let body: String
    }

    static func replace(in context: ModelContext, now: Date = Date()) throws {
        try remove(from: context)
        for entry in entries {
            let poem = Poem(body: entry.body, createdAt: now.addingTimeInterval(-entry.hoursAgo * 3600),
                            sourceSessionID: marker)
            poem.title = entry.title
            poem.poet = entry.speaker
            poem.sourceNote = entry.source
            context.insert(poem)
        }
        try context.save()
    }

    static func remove(from context: ModelContext) throws {
        let marker = marker
        try context.delete(model: Poem.self, where: #Predicate { $0.sourceSessionID == marker })
        try context.save()
    }

    static func count(in context: ModelContext) -> Int {
        let marker = marker
        return (try? context.fetchCount(FetchDescriptor<Poem>(predicate: #Predicate {
            $0.sourceSessionID == marker
        }))) ?? 0
    }

    // Line per phrase with a blank line between stanzas, as transcripts are laid out (D-024).
    static let entries: [Entry] = [
        Entry(title: "Hope is the thing with feathers", speaker: "Emily Dickinson", source: nil, hoursAgo: 0.4,
              body: """
                Hope is the thing with feathers
                That perches in the soul,
                And sings the tune without the words,
                And never stops at all.

                And sweetest in the gale is heard,
                And sore must be the storm
                That could abash the little bird
                That kept so many warm.

                I've heard it in the chillest land,
                And on the strangest sea;
                Yet never, in extremity,
                It asked a crumb of me.
                """),
        Entry(title: "The Gettysburg Address", speaker: "Abraham Lincoln",
              source: "https://www.loc.gov/exhibits/gettysburg-address/", hoursAgo: 5,
              body: """
                Four score and seven years ago
                our fathers brought forth on this continent, a new nation,
                conceived in Liberty,
                and dedicated to the proposition that all men are created equal.

                It is rather for us to be here dedicated
                to the great task remaining before us,
                that this nation, under God, shall have a new birth of freedom,
                and that government of the people, by the people, for the people,
                shall not perish from the earth.
                """),
        Entry(title: "Weekend sourdough", speaker: nil, source: nil, hoursAgo: 26,
              body: """
                Feed the starter the night before.
                Five hundred grams of flour, three hundred and fifty of water.
                Rest for an hour, then add ten grams of salt.

                Four sets of stretch and folds, thirty minutes apart.
                Shape it, and into the fridge overnight.

                Bake at two hundred and fifty, lid on for twenty minutes,
                then lid off for twenty-five, until it is deep brown.
                """),
        Entry(title: "The Road Not Taken", speaker: "Robert Frost", source: nil, hoursAgo: 50,
              body: """
                Two roads diverged in a yellow wood,
                And sorry I could not travel both
                And be one traveler, long I stood
                And looked down one as far as I could
                To where it bent in the undergrowth;

                Then took the other, as just as fair,
                And having perhaps the better claim,
                Because it was grassy and wanted wear;
                Though as for that the passing there
                Had worn them really about the same,

                And both that morning equally lay
                In leaves no step had trodden black.
                Oh, I kept the first for another day!
                Yet knowing how way leads on to way,
                I doubted if I should ever come back.

                I shall be telling this with a sigh
                Somewhere ages and ages hence:
                Two roads diverged in a wood, and I,
                I took the one less traveled by,
                And that has made all the difference.
                """),
        Entry(title: "Inaugural Address", speaker: "John F. Kennedy",
              source: "https://www.jfklibrary.org/learn/about-jfk/historic-speeches/inaugural-address",
              hoursAgo: 75,
              body: """
                And so, my fellow Americans:
                ask not what your country can do for you,
                ask what you can do for your country.

                My fellow citizens of the world:
                ask not what America will do for you,
                but what together we can do for the freedom of man.
                """),
        Entry(title: "Sonnet 18", speaker: "William Shakespeare", source: nil, hoursAgo: 122,
              body: """
                Shall I compare thee to a summer's day?
                Thou art more lovely and more temperate:
                Rough winds do shake the darling buds of May,
                And summer's lease hath all too short a date;

                Sometime too hot the eye of heaven shines,
                And often is his gold complexion dimmed;
                And every fair from fair sometime declines,
                By chance or nature's changing course untrimmed;

                But thy eternal summer shall not fade,
                Nor lose possession of that fair thou ow'st;
                Nor shall death brag thou wander'st in his shade,
                When in eternal lines to time thou grow'st:

                So long as men can breathe or eyes can see,
                So long lives this, and this gives life to thee.
                """),
        Entry(title: "Daffodils", speaker: "William Wordsworth", source: nil, hoursAgo: 170,
              body: """
                I wandered lonely as a cloud
                That floats on high o'er vales and hills,
                When all at once I saw a crowd,
                A host, of golden daffodils;
                Beside the lake, beneath the trees,
                Fluttering and dancing in the breeze.
                """)
    ]
}
#endif
