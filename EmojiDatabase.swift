import Foundation

struct EmojiEntry {
    let emoji: String
    let keywords: [String]
    let relevance: Double
}

/// A small hardcoded set of common emoji. Easy to extend with more entries later.
final class EmojiDatabase {
    static let shared = EmojiDatabase()

    private struct Entry {
        let emoji: String
        let keywords: [String]
    }

    private let entries: [Entry] = [
        Entry(emoji: "😀", keywords: ["grinning", "smile", "happy"]),
        Entry(emoji: "😂", keywords: ["joy", "laugh", "crying", "lol"]),
        Entry(emoji: "😅", keywords: ["sweat", "smile", "relief", "phew"]),
        Entry(emoji: "😉", keywords: ["wink", "flirt"]),
        Entry(emoji: "😍", keywords: ["heart", "eyes", "love", "crush"]),
        Entry(emoji: "😎", keywords: ["cool", "sunglasses"]),
        Entry(emoji: "🤔", keywords: ["thinking", "hmm", "consider"]),
        Entry(emoji: "😢", keywords: ["cry", "sad", "tear"]),
        Entry(emoji: "😭", keywords: ["sob", "crying", "sad", "bawling"]),
        Entry(emoji: "😡", keywords: ["angry", "mad", "rage"]),
        Entry(emoji: "😱", keywords: ["scream", "shocked", "fear"]),
        Entry(emoji: "🥳", keywords: ["party", "celebrate", "birthday"]),
        Entry(emoji: "😴", keywords: ["sleep", "tired", "zzz"]),
        Entry(emoji: "🤯", keywords: ["mindblown", "shocked", "exploding"]),
        Entry(emoji: "🥺", keywords: ["pleading", "puppy", "eyes"]),
        Entry(emoji: "😇", keywords: ["angel", "innocent", "halo"]),
        Entry(emoji: "🙄", keywords: ["eyeroll", "annoyed"]),
        Entry(emoji: "😬", keywords: ["grimace", "awkward", "nervous"]),
        Entry(emoji: "🤷", keywords: ["shrug", "idk", "whatever"]),
        Entry(emoji: "🙌", keywords: ["hands", "raised", "celebrate", "praise"]),
        Entry(emoji: "👍", keywords: ["thumbsup", "yes", "approve", "good", "ok"]),
        Entry(emoji: "👎", keywords: ["thumbsdown", "no", "bad"]),
        Entry(emoji: "👏", keywords: ["clap", "applause", "bravo"]),
        Entry(emoji: "🙏", keywords: ["pray", "please", "thanks", "hope"]),
        Entry(emoji: "💪", keywords: ["muscle", "strong", "flex", "workout"]),
        Entry(emoji: "👋", keywords: ["wave", "hello", "bye"]),
        Entry(emoji: "✌️", keywords: ["peace", "victory"]),
        Entry(emoji: "🤝", keywords: ["handshake", "deal", "agreement"]),
        Entry(emoji: "❤️", keywords: ["heart", "love", "red"]),
        Entry(emoji: "💔", keywords: ["heartbroken", "breakup", "sad"]),
        Entry(emoji: "🔥", keywords: ["fire", "lit", "hot", "flame"]),
        Entry(emoji: "⭐", keywords: ["star", "favorite"]),
        Entry(emoji: "✨", keywords: ["sparkles", "magic", "shiny"]),
        Entry(emoji: "🎉", keywords: ["party", "celebrate", "tada", "congrats"]),
        Entry(emoji: "💯", keywords: ["hundred", "perfect", "score"]),
        Entry(emoji: "💰", keywords: ["money", "bag", "rich"]),
        Entry(emoji: "💡", keywords: ["idea", "lightbulb", "bright"]),
        Entry(emoji: "⚡️", keywords: ["lightning", "fast", "bolt", "electric"]),
        Entry(emoji: "🚀", keywords: ["rocket", "launch", "fast", "startup"]),
        Entry(emoji: "🎯", keywords: ["target", "dart", "goal", "bullseye"]),
        Entry(emoji: "✅", keywords: ["check", "done", "yes", "complete"]),
        Entry(emoji: "❌", keywords: ["x", "no", "cancel", "wrong"]),
        Entry(emoji: "⚠️", keywords: ["warning", "caution", "alert"]),
        Entry(emoji: "❓", keywords: ["question", "confused", "help"]),
        Entry(emoji: "🐶", keywords: ["dog", "puppy", "animal"]),
        Entry(emoji: "🐱", keywords: ["cat", "kitten", "animal"]),
        Entry(emoji: "🦊", keywords: ["fox", "animal"]),
        Entry(emoji: "🐸", keywords: ["frog", "animal"]),
        Entry(emoji: "🐢", keywords: ["turtle", "slow", "animal"]),
        Entry(emoji: "🦄", keywords: ["unicorn", "magic", "animal"]),
        Entry(emoji: "☕️", keywords: ["coffee", "tea", "cafe", "drink"]),
        Entry(emoji: "🍕", keywords: ["pizza", "food"]),
        Entry(emoji: "🍔", keywords: ["burger", "food", "hamburger"]),
        Entry(emoji: "🍺", keywords: ["beer", "drink", "cheers"]),
        Entry(emoji: "🍎", keywords: ["apple", "fruit", "food"]),
        Entry(emoji: "🎂", keywords: ["cake", "birthday", "party"]),
        Entry(emoji: "⚽️", keywords: ["soccer", "football", "sports", "ball"]),
        Entry(emoji: "🏀", keywords: ["basketball", "sports", "ball"]),
        Entry(emoji: "🎮", keywords: ["game", "controller", "gaming"]),
        Entry(emoji: "🎵", keywords: ["music", "note", "song"]),
        Entry(emoji: "📱", keywords: ["phone", "mobile", "iphone"]),
        Entry(emoji: "💻", keywords: ["laptop", "computer", "code"]),
        Entry(emoji: "⌨️", keywords: ["keyboard", "type"]),
        Entry(emoji: "🖱️", keywords: ["mouse", "click"]),
        Entry(emoji: "📁", keywords: ["folder", "file", "directory"]),
        Entry(emoji: "📄", keywords: ["file", "document", "page"]),
        Entry(emoji: "🔒", keywords: ["lock", "secure", "private"]),
        Entry(emoji: "🔑", keywords: ["key", "unlock", "password"]),
        Entry(emoji: "🐛", keywords: ["bug", "insect", "error"]),
        Entry(emoji: "🛠️", keywords: ["tools", "wrench", "build", "fix"]),
        Entry(emoji: "📅", keywords: ["calendar", "date", "schedule"]),
        Entry(emoji: "⏰", keywords: ["alarm", "clock", "time", "reminder"]),
        Entry(emoji: "✈️", keywords: ["plane", "flight", "travel"]),
        Entry(emoji: "🚗", keywords: ["car", "drive", "travel"]),
        Entry(emoji: "🏠", keywords: ["house", "home"]),
        Entry(emoji: "☀️", keywords: ["sun", "sunny", "weather"]),
        Entry(emoji: "🌧️", keywords: ["rain", "weather", "cloud"]),
        Entry(emoji: "🌙", keywords: ["moon", "night"]),
    ]

    func search(query: String) -> [EmojiEntry] {
        guard !query.isEmpty else {
            return entries.prefix(24).map { EmojiEntry(emoji: $0.emoji, keywords: $0.keywords, relevance: 0.5) }
        }

        var results: [EmojiEntry] = []
        for entry in entries {
            let best = entry.keywords.reduce(0.0) { partial, keyword in
                max(partial, SearchEngine.calculateRelevance(text: keyword, query: query))
            }
            guard best > 0 else { continue }
            results.append(EmojiEntry(emoji: entry.emoji, keywords: entry.keywords, relevance: best))
        }
        return results.sorted { $0.relevance > $1.relevance }
    }
}
