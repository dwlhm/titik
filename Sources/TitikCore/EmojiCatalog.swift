import Foundation

public enum EmojiCategory: String, CaseIterable, Sendable {
    case all = "All"
    case smileys = "Smileys & Emotion"
    case people = "People & Body"
    case animals = "Animals & Nature"
    case food = "Food & Drink"
    case travel = "Travel & Places"
    case activities = "Activities"
    case objects = "Objects"
    case symbols = "Symbols"
    case flags = "Flags"

    public var iconName: String {
        switch self {
        case .all: return "sparkles"
        case .smileys: return "face.smiling"
        case .people: return "person.crop.circle"
        case .animals: return "tortoise"
        case .food: return "fork.knife"
        case .travel: return "airplane"
        case .activities: return "sportscourt"
        case .objects: return "lightbulb"
        case .symbols: return "number"
        case .flags: return "flag"
        }
    }
}

public struct EmojiItem: Identifiable, Sendable, Equatable {
    public var id: String { emoji }
    public let emoji: String
    public let name: String
    public let shortcode: String      // e.g. ":fire:"
    public let category: EmojiCategory
    public let keywords: [String]
    public let unicodeHex: String     // e.g. "U+1F525"

    public init(
        emoji: String,
        name: String,
        shortcode: String,
        category: EmojiCategory,
        keywords: [String] = [],
        unicodeHex: String = ""
    ) {
        self.emoji = emoji
        self.name = name
        self.shortcode = shortcode
        self.category = category
        self.keywords = keywords
        self.unicodeHex = unicodeHex
    }
}

public final class EmojiCatalog: @unchecked Sendable {
    public static let shared = EmojiCatalog()

    public let allEmojis: [EmojiItem]
    private let categoryMap: [EmojiCategory: [EmojiItem]]

    public init() {
        let emojis = Self.buildDatabase()
        self.allEmojis = emojis

        var map: [EmojiCategory: [EmojiItem]] = [:]
        for cat in EmojiCategory.allCases {
            if cat == .all {
                map[.all] = emojis
            } else {
                map[cat] = emojis.filter { $0.category == cat }
            }
        }
        self.categoryMap = map
    }

    public func search(query: String, category: EmojiCategory? = nil) -> [EmojiItem] {
        let targetCategory = category ?? .all
        let sourceList = categoryMap[targetCategory] ?? allEmojis

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return sourceList
        }

        // Clean shortcode query if user typed leading/trailing colon
        let stripped = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        var scoredItems: [(item: EmojiItem, score: Int)] = []

        for item in sourceList {
            var bestScore = 0

            // Direct emoji match
            if item.emoji == trimmed {
                bestScore = max(bestScore, 1000)
            }

            let itemName = item.name.lowercased()
            let itemShortcode = item.shortcode.lowercased()
            let rawShortcode = itemShortcode.trimmingCharacters(in: CharacterSet(charactersIn: ":"))

            // Shortcode exact / prefix match
            if rawShortcode == stripped {
                bestScore = max(bestScore, 900)
            } else if rawShortcode.hasPrefix(stripped) {
                bestScore = max(bestScore, 750)
            } else if rawShortcode.contains(stripped) {
                bestScore = max(bestScore, 500)
            }

            // Name exact / prefix / substring match
            if itemName == trimmed {
                bestScore = max(bestScore, 850)
            } else if itemName.hasPrefix(trimmed) {
                bestScore = max(bestScore, 700)
            } else if itemName.contains(trimmed) {
                bestScore = max(bestScore, 450)
            }

            // Keyword matches
            for kw in item.keywords {
                let kwLower = kw.lowercased()
                if kwLower == stripped {
                    bestScore = max(bestScore, 650)
                } else if kwLower.hasPrefix(stripped) {
                    bestScore = max(bestScore, 400)
                } else if kwLower.contains(stripped) {
                    bestScore = max(bestScore, 300)
                }
            }

            // Unicode Hex match (e.g., U+1F525 or 1F525)
            let hexClean = item.unicodeHex.lowercased().replacingOccurrences(of: "u+", with: "")
            let queryHexClean = stripped.replacingOccurrences(of: "u+", with: "")
            if !queryHexClean.isEmpty && hexClean.contains(queryHexClean) {
                bestScore = max(bestScore, 350)
            }

            // Fuzzy match fallback
            if bestScore == 0 {
                if let match = FuzzyMatcher.match(query: stripped, target: item.name) {
                    bestScore = max(bestScore, match.score)
                } else if let match = FuzzyMatcher.match(query: stripped, target: rawShortcode) {
                    bestScore = max(bestScore, match.score)
                }
            }

            if bestScore > 0 {
                scoredItems.append((item, bestScore))
            }
        }

        scoredItems.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.item.name < rhs.item.name
        }

        return scoredItems.map { $0.item }
    }

    private static func buildDatabase() -> [EmojiItem] {
        return [
            // Smileys & Emotion
            EmojiItem(emoji: "😀", name: "Grinning Face", shortcode: ":grinning:", category: .smileys, keywords: ["face", "smile", "happy", "joy"], unicodeHex: "U+1F600"),
            EmojiItem(emoji: "😃", name: "Grinning Face with Big Eyes", shortcode: ":smiley:", category: .smileys, keywords: ["face", "happy", "joy", "haha"], unicodeHex: "U+1F603"),
            EmojiItem(emoji: "😄", name: "Grinning Face with Smiling Eyes", shortcode: ":smile:", category: .smileys, keywords: ["face", "happy", "laugh", "joy"], unicodeHex: "U+1F604"),
            EmojiItem(emoji: "😁", name: "Beaming Face with Smiling Eyes", shortcode: ":grin:", category: .smileys, keywords: ["face", "happy", "smile", "cheerful"], unicodeHex: "U+1F601"),
            EmojiItem(emoji: "😆", name: "Grinning Squinting Face", shortcode: ":laughing:", category: .smileys, keywords: ["happy", "haha", "laugh", "glad"], unicodeHex: "U+1F606"),
            EmojiItem(emoji: "😅", name: "Grinning Face with Sweat", shortcode: ":sweat_smile:", category: .smileys, keywords: ["face", "hot", "happy", "relief"], unicodeHex: "U+1F605"),
            EmojiItem(emoji: "🤣", name: "Rolling on the Floor Laughing", shortcode: ":rofl:", category: .smileys, keywords: ["face", "rolling", "laughing", "lol", "hilarious"], unicodeHex: "U+1F923"),
            EmojiItem(emoji: "😂", name: "Face with Tears of Joy", shortcode: ":joy:", category: .smileys, keywords: ["face", "tears", "joy", "laugh", "crying"], unicodeHex: "U+1F602"),
            EmojiItem(emoji: "🙂", name: "Slightly Smiling Face", shortcode: ":slightly_smiling_face:", category: .smileys, keywords: ["face", "smile"], unicodeHex: "U+1F642"),
            EmojiItem(emoji: "🙃", name: "Upside-Down Face", shortcode: ":upside_down_face:", category: .smileys, keywords: ["face", "flipped", "sarcastic"], unicodeHex: "U+1F643"),
            EmojiItem(emoji: "🫠", name: "Melting Face", shortcode: ":melting_face:", category: .smileys, keywords: ["hot", "heat", "disappear", "awkward"], unicodeHex: "U+1FAE0"),
            EmojiItem(emoji: "😉", name: "Winking Face", shortcode: ":wink:", category: .smileys, keywords: ["face", "wink", "flirt"], unicodeHex: "U+1F609"),
            EmojiItem(emoji: "😊", name: "Smiling Face with Smiling Eyes", shortcode: ":blush:", category: .smileys, keywords: ["face", "smile", "blush", "proud"], unicodeHex: "U+1F60A"),
            EmojiItem(emoji: "😇", name: "Smiling Face with Halo", shortcode: ":innocent:", category: .smileys, keywords: ["face", "angel", "halo", "innocent"], unicodeHex: "U+1F607"),
            EmojiItem(emoji: "🥰", name: "Smiling Face with Hearts", shortcode: ":smiling_face_with_3_hearts:", category: .smileys, keywords: ["face", "love", "hearts", "crush"], unicodeHex: "U+1F970"),
            EmojiItem(emoji: "😍", name: "Smiling Face with Heart-Eyes", shortcode: ":heart_eyes:", category: .smileys, keywords: ["face", "love", "heart", "eyes", "adoration"], unicodeHex: "U+1F60D"),
            EmojiItem(emoji: "🤩", name: "Star-Struck", shortcode: ":star_struck:", category: .smileys, keywords: ["face", "star", "eyes", "amazed", "wow"], unicodeHex: "U+1F929"),
            EmojiItem(emoji: "😘", name: "Face Blowing a Kiss", shortcode: ":kissing_heart:", category: .smileys, keywords: ["face", "kiss", "love", "flirt"], unicodeHex: "U+1F618"),
            EmojiItem(emoji: "😋", name: "Face Savoring Food", shortcode: ":yum:", category: .smileys, keywords: ["face", "tongue", "delicious", "yum"], unicodeHex: "U+1F60B"),
            EmojiItem(emoji: "😛", name: "Face with Tongue", shortcode: ":stuck_out_tongue:", category: .smileys, keywords: ["face", "tongue", "playful"], unicodeHex: "U+1F61B"),
            EmojiItem(emoji: "😜", name: "Winking Face with Tongue", shortcode: ":stuck_out_tongue_winking_eye:", category: .smileys, keywords: ["face", "wink", "tongue", "crazy"], unicodeHex: "U+1F61C"),
            EmojiItem(emoji: "🤪", name: "Zany Face", shortcode: ":zany_face:", category: .smileys, keywords: ["face", "goofy", "wild", "crazy"], unicodeHex: "U+1F92A"),
            EmojiItem(emoji: "😝", name: "Squinting Face with Tongue", shortcode: ":stuck_out_tongue_closed_eyes:", category: .smileys, keywords: ["face", "tongue", "playful", "prank"], unicodeHex: "U+1F61D"),
            EmojiItem(emoji: "🤑", name: "Money-Mouth Face", shortcode: ":money_mouth_face:", category: .smileys, keywords: ["face", "rich", "money", "dollar"], unicodeHex: "U+1F911"),
            EmojiItem(emoji: "🤗", name: "Smiling Face with Open Hands", shortcode: ":hugs:", category: .smileys, keywords: ["face", "hug", "welcome"], unicodeHex: "U+1F917"),
            EmojiItem(emoji: "🤭", name: "Face with Hand Over Mouth", shortcode: ":hand_over_mouth:", category: .smileys, keywords: ["face", "giggle", "oops", "secret"], unicodeHex: "U+1F92D"),
            EmojiItem(emoji: "🤫", name: "Shushing Face", shortcode: ":shushing_face:", category: .smileys, keywords: ["face", "quiet", "shh", "silent"], unicodeHex: "U+1F92B"),
            EmojiItem(emoji: "🤔", name: "Thinking Face", shortcode: ":thinking:", category: .smileys, keywords: ["face", "think", "ponder", "wonder", "idea"], unicodeHex: "U+1F914"),
            EmojiItem(emoji: "🫡", name: "Saluting Face", shortcode: ":saluting_face:", category: .smileys, keywords: ["face", "salute", "respect", "yes sir"], unicodeHex: "U+1FAE1"),
            EmojiItem(emoji: "🤐", name: "Zipper-Mouth Face", shortcode: ":zipper_mouth_face:", category: .smileys, keywords: ["face", "quiet", "sealed", "secret"], unicodeHex: "U+1F910"),
            EmojiItem(emoji: "🤨", name: "Face with Raised Eyebrow", shortcode: ":raised_eyebrow:", category: .smileys, keywords: ["face", "skeptical", "suspicious", "doubt"], unicodeHex: "U+1F928"),
            EmojiItem(emoji: "😐", name: "Neutral Face", shortcode: ":neutral_face:", category: .smileys, keywords: ["face", "neutral", "meh", "indifferent"], unicodeHex: "U+1F610"),
            EmojiItem(emoji: "😑", name: "Expressionless Face", shortcode: ":expressionless:", category: .smileys, keywords: ["face", "blank", "unimpressed"], unicodeHex: "U+1F611"),
            EmojiItem(emoji: "😶", name: "Face Without Mouth", shortcode: ":no_mouth:", category: .smileys, keywords: ["face", "mute", "speechless"], unicodeHex: "U+1F636"),
            EmojiItem(emoji: "🫥", name: "Dotted Line Face", shortcode: ":dotted_line_face:", category: .smileys, keywords: ["face", "invisible", "hidden", "vanish"], unicodeHex: "U+1FAE5"),
            EmojiItem(emoji: "😏", name: "Smirking Face", shortcode: ":smirk:", category: .smileys, keywords: ["face", "smug", "flirt", "suggestive"], unicodeHex: "U+1F60F"),
            EmojiItem(emoji: "😒", name: "Unamused Face", shortcode: ":unamused:", category: .smileys, keywords: ["face", "annoyed", "unimpressed", "side-eye"], unicodeHex: "U+1F612"),
            EmojiItem(emoji: "🙄", name: "Face with Rolling Eyes", shortcode: ":roll_eyes:", category: .smileys, keywords: ["face", "eyeroll", "frustrated", "bored"], unicodeHex: "U+1F644"),
            EmojiItem(emoji: "😬", name: "Grimacing Face", shortcode: ":grimacing:", category: .smileys, keywords: ["face", "awkward", "nervous", "yikes"], unicodeHex: "U+1F62C"),
            EmojiItem(emoji: "🤥", name: "Lying Face", shortcode: ":lying_face:", category: .smileys, keywords: ["face", "lie", "pinocchio", "long nose"], unicodeHex: "U+1F925"),
            EmojiItem(emoji: "😌", name: "Relieved Face", shortcode: ":relieved:", category: .smileys, keywords: ["face", "peaceful", "calm", "zen"], unicodeHex: "U+1F60C"),
            EmojiItem(emoji: "😔", name: "Pensive Face", shortcode: ":pensive:", category: .smileys, keywords: ["face", "sad", "downcast", "reflective"], unicodeHex: "U+1F614"),
            EmojiItem(emoji: "😪", name: "Sleepy Face", shortcode: ":sleepy:", category: .smileys, keywords: ["face", "tired", "sleep", "snooze"], unicodeHex: "U+1F62A"),
            EmojiItem(emoji: "🤤", name: "Drooling Face", shortcode: ":drooling_face:", category: .smileys, keywords: ["face", "drool", "craving", "sleepy"], unicodeHex: "U+1F924"),
            EmojiItem(emoji: "😴", name: "Sleeping Face", shortcode: ":sleeping:", category: .smileys, keywords: ["face", "sleep", "zzz", "night"], unicodeHex: "U+1F634"),
            EmojiItem(emoji: "😷", name: "Face with Medical Mask", shortcode: ":mask:", category: .smileys, keywords: ["face", "sick", "doctor", "health", "corona"], unicodeHex: "U+1F637"),
            EmojiItem(emoji: "🤒", name: "Face with Thermometer", shortcode: ":face_with_thermometer:", category: .smileys, keywords: ["face", "ill", "fever", "sick"], unicodeHex: "U+1F912"),
            EmojiItem(emoji: "🤕", name: "Face with Head-Bandage", shortcode: ":face_with_head_bandage:", category: .smileys, keywords: ["face", "hurt", "injured", "accident"], unicodeHex: "U+1F915"),
            EmojiItem(emoji: "🤢", name: "Nauseated Face", shortcode: ":nauseated_face:", category: .smileys, keywords: ["face", "gross", "sick", "vomit"], unicodeHex: "U+1F922"),
            EmojiItem(emoji: "🤮", name: "Face Vomiting", shortcode: ":vomiting_face:", category: .smileys, keywords: ["face", "puke", "gross", "sick"], unicodeHex: "U+1F92E"),
            EmojiItem(emoji: "🤧", name: "Sneezing Face", shortcode: ":sneezing_face:", category: .smileys, keywords: ["face", "sneeze", "cold", "tissue"], unicodeHex: "U+1F927"),
            EmojiItem(emoji: "🥵", name: "Hot Face", shortcode: ":hot_face:", category: .smileys, keywords: ["face", "hot", "sweat", "summer"], unicodeHex: "U+1F975"),
            EmojiItem(emoji: "🥶", name: "Cold Face", shortcode: ":cold_face:", category: .smileys, keywords: ["face", "freezing", "ice", "winter"], unicodeHex: "U+1F976"),
            EmojiItem(emoji: "🥴", name: "Woozy Face", shortcode: ":woozy_face:", category: .smileys, keywords: ["face", "dizzy", "drunk", "tipsy"], unicodeHex: "U+1F974"),
            EmojiItem(emoji: "😵", name: "Dizzy Face", shortcode: ":dizzy_face:", category: .smileys, keywords: ["face", "ko", "confused", "spin"], unicodeHex: "U+1F635"),
            EmojiItem(emoji: "🤯", name: "Exploding Head", shortcode: ":exploding_head:", category: .smileys, keywords: ["face", "mind blown", "shock", "boom"], unicodeHex: "U+1F92F"),
            EmojiItem(emoji: "🤠", name: "Cowboy Hat Face", shortcode: ":cowboy_hat_face:", category: .smileys, keywords: ["face", "cowboy", "western", "yeehaw"], unicodeHex: "U+1F920"),
            EmojiItem(emoji: "🥳", name: "Partying Face", shortcode: ":partying_face:", category: .smileys, keywords: ["face", "celebrate", "party", "horn", "confetti"], unicodeHex: "U+1F973"),
            EmojiItem(emoji: "😎", name: "Smiling Face with Sunglasses", shortcode: ":sunglasses:", category: .smileys, keywords: ["face", "cool", "shades", "awesome"], unicodeHex: "U+1F60E"),
            EmojiItem(emoji: "🤓", name: "Nerd Face", shortcode: ":nerd_face:", category: .smileys, keywords: ["face", "nerd", "geek", "glasses", "smart"], unicodeHex: "U+1F913"),
            EmojiItem(emoji: "🧐", name: "Face with Monocle", shortcode: ":monocle_face:", category: .smileys, keywords: ["face", "fancy", "curious", "investigate"], unicodeHex: "U+1F9D0"),
            EmojiItem(emoji: "😕", name: "Confused Face", shortcode: ":confused:", category: .smileys, keywords: ["face", "puzzled", "lost"], unicodeHex: "U+1F615"),
            EmojiItem(emoji: "😟", name: "Worried Face", shortcode: ":worried:", category: .smileys, keywords: ["face", "concern", "nervous"], unicodeHex: "U+1F61F"),
            EmojiItem(emoji: "🙁", name: "Slightly Frowning Face", shortcode: ":slightly_frowning_face:", category: .smileys, keywords: ["face", "sad", "disappointed"], unicodeHex: "U+1F641"),
            EmojiItem(emoji: "😮", name: "Face with Open Mouth", shortcode: ":open_mouth:", category: .smileys, keywords: ["face", "surprise", "wow"], unicodeHex: "U+1F62E"),
            EmojiItem(emoji: "😲", name: "Astonished Face", shortcode: ":astonished:", category: .smileys, keywords: ["face", "shock", "amazed"], unicodeHex: "U+1F632"),
            EmojiItem(emoji: "😳", name: "Flushed Face", shortcode: ":flushed:", category: .smileys, keywords: ["face", "embarrassed", "shy", "blush"], unicodeHex: "U+1F633"),
            EmojiItem(emoji: "🥺", name: "Pleading Face", shortcode: ":pleading_face:", category: .smileys, keywords: ["face", "puppy eyes", "please", "beg"], unicodeHex: "U+1F97A"),
            EmojiItem(emoji: "🥹", name: "Face Holding Back Tears", shortcode: ":holding_back_tears:", category: .smileys, keywords: ["face", "touched", "grateful", "proud"], unicodeHex: "U+1F979"),
            EmojiItem(emoji: "😦", name: "Frowning Face with Open Mouth", shortcode: ":frowning:", category: .smileys, keywords: ["face", "gasp", "scared"], unicodeHex: "U+1F626"),
            EmojiItem(emoji: "😨", name: "Fearful Face", shortcode: ":fearful:", category: .smileys, keywords: ["face", "scared", "afraid"], unicodeHex: "U+1F628"),
            EmojiItem(emoji: "😰", name: "Anxious Face with Sweat", shortcode: ":cold_sweat:", category: .smileys, keywords: ["face", "nervous", "anxiety", "blue"], unicodeHex: "U+1F630"),
            EmojiItem(emoji: "😥", name: "Sad but Relieved Face", shortcode: ":disappointed_relieved:", category: .smileys, keywords: ["face", "close call", "sigh"], unicodeHex: "U+1F625"),
            EmojiItem(emoji: "😢", name: "Crying Face", shortcode: ":cry:", category: .smileys, keywords: ["face", "tear", "sad", "unhappy"], unicodeHex: "U+1F622"),
            EmojiItem(emoji: "😭", name: "Loudly Crying Face", shortcode: ":sob:", category: .smileys, keywords: ["face", "cry", "tears", "sad", "bawling"], unicodeHex: "U+1F62D"),
            EmojiItem(emoji: "😱", name: "Face Screaming in Fear", shortcode: ":scream:", category: .smileys, keywords: ["face", "munch", "horror", "shock"], unicodeHex: "U+1F631"),
            EmojiItem(emoji: "😖", name: "Confounded Face", shortcode: ":confounded:", category: .smileys, keywords: ["face", "frustrated", "struggle"], unicodeHex: "U+1F616"),
            EmojiItem(emoji: "😣", name: "Persevering Face", shortcode: ":persevere:", category: .smileys, keywords: ["face", "try hard", "endure"], unicodeHex: "U+1F623"),
            EmojiItem(emoji: "😞", name: "Disappointed Face", shortcode: ":disappointed:", category: .smileys, keywords: ["face", "letdown", "sad"], unicodeHex: "U+1F61E"),
            EmojiItem(emoji: "😓", name: "Downcast Face with Sweat", shortcode: ":sweat:", category: .smileys, keywords: ["face", "tired", "exhausted"], unicodeHex: "U+1F613"),
            EmojiItem(emoji: "😩", name: "Weary Face", shortcode: ":weary:", category: .smileys, keywords: ["face", "tired", "stressed"], unicodeHex: "U+1F629"),
            EmojiItem(emoji: "😫", name: "Tired Face", shortcode: ":tired_face:", category: .smileys, keywords: ["face", "exhausted", "done"], unicodeHex: "U+1F62B"),
            EmojiItem(emoji: "🥱", name: "Yawning Face", shortcode: ":yawning_face:", category: .smileys, keywords: ["face", "yawn", "sleepy", "bored"], unicodeHex: "U+1F971"),
            EmojiItem(emoji: "😤", name: "Face with Steam From Nose", shortcode: ":triumph:", category: .smileys, keywords: ["face", "proud", "huff", "angry"], unicodeHex: "U+1F624"),
            EmojiItem(emoji: "😡", name: "Enraged Face", shortcode: ":rage:", category: .smileys, keywords: ["face", "angry", "mad", "red"], unicodeHex: "U+1F621"),
            EmojiItem(emoji: "😠", name: "Angry Face", shortcode: ":angry:", category: .smileys, keywords: ["face", "mad", "grumpy"], unicodeHex: "U+1F620"),
            EmojiItem(emoji: "🤬", name: "Face with Symbols on Mouth", shortcode: ":cursing_face:", category: .smileys, keywords: ["face", "swear", "curse", "censored", "furious"], unicodeHex: "U+1F92C"),
            EmojiItem(emoji: "😈", name: "Smiling Face with Horns", shortcode: ":smiling_imp:", category: .smileys, keywords: ["devil", "evil", "mischief"], unicodeHex: "U+1F608"),
            EmojiItem(emoji: "👿", name: "Angry Face with Horns", shortcode: ":imp:", category: .smileys, keywords: ["devil", "mad", "demon"], unicodeHex: "U+1F47F"),
            EmojiItem(emoji: "💀", name: "Skull", shortcode: ":skull:", category: .smileys, keywords: ["dead", "death", "skeleton", "dying laughing"], unicodeHex: "U+1F480"),
            EmojiItem(emoji: "☠️", name: "Skull and Crossbones", shortcode: ":skull_and_crossbones:", category: .smileys, keywords: ["danger", "pirate", "poison"], unicodeHex: "U+2620"),
            EmojiItem(emoji: "💩", name: "Pile of Poo", shortcode: ":poop:", category: .smileys, keywords: ["poo", "crap", "funny"], unicodeHex: "U+1F4A9"),
            EmojiItem(emoji: "🤡", name: "Clown Face", shortcode: ":clown_face:", category: .smileys, keywords: ["clown", "circus", "fool"], unicodeHex: "U+1F921"),
            EmojiItem(emoji: "👻", name: "Ghost", shortcode: ":ghost:", category: .smileys, keywords: ["spooky", "halloween", "spirit"], unicodeHex: "U+1F47B"),
            EmojiItem(emoji: "👽", name: "Alien", shortcode: ":alien:", category: .smileys, keywords: ["ufo", "space", "extraterrestrial"], unicodeHex: "U+1F47D"),
            EmojiItem(emoji: "👾", name: "Alien Monster", shortcode: ":space_invader:", category: .smileys, keywords: ["game", "arcade", "retro", "pixel"], unicodeHex: "U+1F47E"),
            EmojiItem(emoji: "🤖", name: "Robot", shortcode: ":robot:", category: .smileys, keywords: ["bot", "ai", "machine", "tech"], unicodeHex: "U+1F916"),

            // People & Body
            EmojiItem(emoji: "👋", name: "Waving Hand", shortcode: ":wave:", category: .people, keywords: ["hand", "hello", "goodbye", "wave"], unicodeHex: "U+1F44B"),
            EmojiItem(emoji: "🤚", name: "Raised Back of Hand", shortcode: ":raised_back_of_hand:", category: .people, keywords: ["hand", "backhand"], unicodeHex: "U+1F91A"),
            EmojiItem(emoji: "🖐️", name: "Hand with Fingers Splayed", shortcode: ":raised_hand_with_fingers_splayed:", category: .people, keywords: ["hand", "five", "stop"], unicodeHex: "U+1F590"),
            EmojiItem(emoji: "✋", name: "Raised Hand", shortcode: ":hand:", category: .people, keywords: ["hand", "high five", "stop"], unicodeHex: "U+270B"),
            EmojiItem(emoji: "🖖", name: "Vulcan Salute", shortcode: ":vulcan_salute:", category: .people, keywords: ["spock", "star trek", "live long and prosper"], unicodeHex: "U+1F596"),
            EmojiItem(emoji: "🫱", name: "Rightwards Hand", shortcode: ":rightwards_hand:", category: .people, keywords: ["hand", "right", "reach"], unicodeHex: "U+1FAF1"),
            EmojiItem(emoji: "🫲", name: "Leftwards Hand", shortcode: ":leftwards_hand:", category: .people, keywords: ["hand", "left", "reach"], unicodeHex: "U+1FAF2"),
            EmojiItem(emoji: "🫳", name: "Palm Down Hand", shortcode: ":palm_down_hand:", category: .people, keywords: ["hand", "drop", "dismiss"], unicodeHex: "U+1FAF3"),
            EmojiItem(emoji: "🫴", name: "Palm Up Hand", shortcode: ":palm_up_hand:", category: .people, keywords: ["hand", "beckon", "catch"], unicodeHex: "U+1FAF4"),
            EmojiItem(emoji: "👌", name: "OK Hand", shortcode: ":ok_hand:", category: .people, keywords: ["ok", "perfect", "good", "agree"], unicodeHex: "U+1F44C"),
            EmojiItem(emoji: "🤌", name: "Pinched Fingers", shortcode: ":pinched_fingers:", category: .people, keywords: ["italian", "what do you want", "gesture"], unicodeHex: "U+1F90C"),
            EmojiItem(emoji: "🤏", name: "Pinching Hand", shortcode: ":pinching_hand:", category: .people, keywords: ["small", "tiny", "little bit"], unicodeHex: "U+1F90F"),
            EmojiItem(emoji: "✌️", name: "Victory Hand", shortcode: ":v:", category: .people, keywords: ["peace", "victory", "two"], unicodeHex: "U+270C"),
            EmojiItem(emoji: "🤞", name: "Crossed Fingers", shortcode: ":crossed_fingers:", category: .people, keywords: ["luck", "hopeful", "wish"], unicodeHex: "U+1F91E"),
            EmojiItem(emoji: "🫰", name: "Hand with Index Finger and Thumb Crossed", shortcode: ":hand_with_index_finger_and_thumb_crossed:", category: .people, keywords: ["finger heart", "love", "kpop", "money"], unicodeHex: "U+1FAF0"),
            EmojiItem(emoji: "🤟", name: "Love-You Gesture", shortcode: ":love_you_gesture:", category: .people, keywords: ["ily", "sign language", "rock"], unicodeHex: "U+1F91F"),
            EmojiItem(emoji: "🤘", name: "Sign of the Horns", shortcode: ":metal:", category: .people, keywords: ["rock on", "heavy metal"], unicodeHex: "U+1F918"),
            EmojiItem(emoji: "🤙", name: "Call Me Hand", shortcode: ":call_me_hand:", category: .people, keywords: ["shaka", "hang loose", "phone"], unicodeHex: "U+1F919"),
            EmojiItem(emoji: "👈", name: "Backhand Index Pointing Left", shortcode: ":point_left:", category: .people, keywords: ["point", "left", "direction"], unicodeHex: "U+1F448"),
            EmojiItem(emoji: "👉", name: "Backhand Index Pointing Right", shortcode: ":point_right:", category: .people, keywords: ["point", "right", "direction"], unicodeHex: "U+1F449"),
            EmojiItem(emoji: "👆", name: "Backhand Index Pointing Up", shortcode: ":point_up_2:", category: .people, keywords: ["point", "up", "top"], unicodeHex: "U+1F446"),
            EmojiItem(emoji: "🖕", name: "Middle Finger", shortcode: ":middle_finger:", category: .people, keywords: ["rude", "gesture"], unicodeHex: "U+1F595"),
            EmojiItem(emoji: "👇", name: "Backhand Index Pointing Down", shortcode: ":point_down:", category: .people, keywords: ["point", "down", "below"], unicodeHex: "U+1F447"),
            EmojiItem(emoji: "☝️", name: "Index Pointing Up", shortcode: ":point_up:", category: .people, keywords: ["point", "first", "listen"], unicodeHex: "U+261D"),
            EmojiItem(emoji: "🫵", name: "Index Pointing at the Viewer", shortcode: ":pointing_at_you:", category: .people, keywords: ["you", "point", "target"], unicodeHex: "U+1FAF5"),
            EmojiItem(emoji: "👍", name: "Thumbs Up", shortcode: ":thumbsup:", category: .people, keywords: ["yes", "agree", "good", "like", "+1"], unicodeHex: "U+1F44D"),
            EmojiItem(emoji: "👎", name: "Thumbs Down", shortcode: ":thumbsdown:", category: .people, keywords: ["no", "dislike", "bad", "-1"], unicodeHex: "U+1F44E"),
            EmojiItem(emoji: "✊", name: "Raised Fist", shortcode: ":fist_raised:", category: .people, keywords: ["power", "strength", "solidarity"], unicodeHex: "U+270A"),
            EmojiItem(emoji: "👊", name: "Oncoming Fist", shortcode: ":fist_oncoming:", category: .people, keywords: ["punch", "fist bump"], unicodeHex: "U+1F44A"),
            EmojiItem(emoji: "🤛", name: "Left-Facing Fist", shortcode: ":fist_left:", category: .people, keywords: ["fist bump", "left"], unicodeHex: "U+1F91B"),
            EmojiItem(emoji: "🤜", name: "Right-Facing Fist", shortcode: ":fist_right:", category: .people, keywords: ["fist bump", "right"], unicodeHex: "U+1F91C"),
            EmojiItem(emoji: "👏", name: "Clapping Hands", shortcode: ":clap:", category: .people, keywords: ["applause", "praise", "bravo"], unicodeHex: "U+1F44F"),
            EmojiItem(emoji: "🙌", name: "Raising Hands", shortcode: ":raised_hands:", category: .people, keywords: ["celebrate", "hooray", "hallelujah"], unicodeHex: "U+1F64C"),
            EmojiItem(emoji: "🫶", name: "Heart Hands", shortcode: ":heart_hands:", category: .people, keywords: ["love", "heart", "appreciation"], unicodeHex: "U+1FAF6"),
            EmojiItem(emoji: "👐", name: "Open Hands", shortcode: ":open_hands:", category: .people, keywords: ["open", "hug", "give"], unicodeHex: "U+1F450"),
            EmojiItem(emoji: "🤲", name: "Palms Up Together", shortcode: ":palms_up_together:", category: .people, keywords: ["prayer", "offering", "dua"], unicodeHex: "U+1F932"),
            EmojiItem(emoji: "🤝", name: "Handshake", shortcode: ":handshake:", category: .people, keywords: ["deal", "agreement", "greeting", "partnership"], unicodeHex: "U+1F91D"),
            EmojiItem(emoji: "🙏", name: "Folded Hands", shortcode: ":pray:", category: .people, keywords: ["please", "thank you", "namaste", "pray", "bless"], unicodeHex: "U+1F64F"),
            EmojiItem(emoji: "✍️", name: "Writing Hand", shortcode: ":writing_hand:", category: .people, keywords: ["write", "author", "compose"], unicodeHex: "U+270D"),
            EmojiItem(emoji: "💅", name: "Nail Polish", shortcode: ":nail_care:", category: .people, keywords: ["beauty", "glamour", "slay", "unbothered"], unicodeHex: "U+1F485"),
            EmojiItem(emoji: "🤳", name: "Selfie", shortcode: ":selfie:", category: .people, keywords: ["camera", "phone", "photo"], unicodeHex: "U+1F933"),
            EmojiItem(emoji: "💪", name: "Flexed Biceps", shortcode: ":muscle:", category: .people, keywords: ["strong", "flex", "workout", "power", "gym"], unicodeHex: "U+1F4AA"),
            EmojiItem(emoji: "🧠", name: "Brain", shortcode: ":brain:", category: .people, keywords: ["smart", "mind", "intellect", "think"], unicodeHex: "U+1F9E0"),
            EmojiItem(emoji: "👀", name: "Eyes", shortcode: ":eyes:", category: .people, keywords: ["look", "see", "watch", "peep", "curious"], unicodeHex: "U+1F440"),
            EmojiItem(emoji: "👁️", name: "Eye", shortcode: ":eye:", category: .people, keywords: ["look", "vision"], unicodeHex: "U+1F441"),
            EmojiItem(emoji: "👅", name: "Tongue", shortcode: ":tongue:", category: .people, keywords: ["taste", "lick"], unicodeHex: "U+1F445"),
            EmojiItem(emoji: "👄", name: "Mouth", shortcode: ":lips:", category: .people, keywords: ["kiss", "lips"], unicodeHex: "U+1F444"),

            // Animals & Nature
            EmojiItem(emoji: "🐶", name: "Dog Face", shortcode: ":dog:", category: .animals, keywords: ["dog", "puppy", "pet", "bark"], unicodeHex: "U+1F436"),
            EmojiItem(emoji: "🐱", name: "Cat Face", shortcode: ":cat:", category: .animals, keywords: ["cat", "kitten", "meow", "pet"], unicodeHex: "U+1F431"),
            EmojiItem(emoji: "🐭", name: "Mouse Face", shortcode: ":mouse:", category: .animals, keywords: ["mouse", "rodent"], unicodeHex: "U+1F42D"),
            EmojiItem(emoji: "🐹", name: "Hamster", shortcode: ":hamster:", category: .animals, keywords: ["hamster", "pet"], unicodeHex: "U+1F439"),
            EmojiItem(emoji: "🐰", name: "Rabbit Face", shortcode: ":rabbit:", category: .animals, keywords: ["bunny", "rabbit", "easter"], unicodeHex: "U+1F430"),
            EmojiItem(emoji: "🦊", name: "Fox", shortcode: ":fox_face:", category: .animals, keywords: ["fox", "cunning", "wild"], unicodeHex: "U+1F98A"),
            EmojiItem(emoji: "🐻", name: "Bear", shortcode: ":bear:", category: .animals, keywords: ["bear", "grizzly"], unicodeHex: "U+1F43B"),
            EmojiItem(emoji: "🐼", name: "Panda", shortcode: ":panda_face:", category: .animals, keywords: ["panda", "bamboo", "china"], unicodeHex: "U+1F43C"),
            EmojiItem(emoji: "🐻‍❄️", name: "Polar Bear", shortcode: ":polar_bear:", category: .animals, keywords: ["polar", "arctic", "white bear"], unicodeHex: "U+1F43B-200D-2744"),
            EmojiItem(emoji: "🐨", name: "Koala", shortcode: ":koala:", category: .animals, keywords: ["koala", "australia", "eucalyptus"], unicodeHex: "U+1F428"),
            EmojiItem(emoji: "🐯", name: "Tiger Face", shortcode: ":tiger:", category: .animals, keywords: ["tiger", "wild", "stripes"], unicodeHex: "U+1F42F"),
            EmojiItem(emoji: "🦁", name: "Lion", shortcode: ":lion:", category: .animals, keywords: ["lion", "king", "safari"], unicodeHex: "U+1F981"),
            EmojiItem(emoji: "🐮", name: "Cow Face", shortcode: ":cow:", category: .animals, keywords: ["cow", "moo", "milk"], unicodeHex: "U+1F42E"),
            EmojiItem(emoji: "🐷", name: "Pig Face", shortcode: ":pig:", category: .animals, keywords: ["pig", "oink", "farm"], unicodeHex: "U+1F437"),
            EmojiItem(emoji: "🐸", name: "Frog", shortcode: ":frog:", category: .animals, keywords: ["frog", "toad", "amphibian"], unicodeHex: "U+1F438"),
            EmojiItem(emoji: "🐵", name: "Monkey Face", shortcode: ":monkey_face:", category: .animals, keywords: ["monkey", "jungle"], unicodeHex: "U+1F435"),
            EmojiItem(emoji: "🐔", name: "Chicken", shortcode: ":chicken:", category: .animals, keywords: ["chicken", "rooster", "farm"], unicodeHex: "U+1F414"),
            EmojiItem(emoji: "🐧", name: "Penguin", shortcode: ":penguin:", category: .animals, keywords: ["penguin", "antarctica", "bird", "linux"], unicodeHex: "U+1F427"),
            EmojiItem(emoji: "🦅", name: "Eagle", shortcode: ":eagle:", category: .animals, keywords: ["eagle", "america", "freedom", "bird"], unicodeHex: "U+1F985"),
            EmojiItem(emoji: "🦆", name: "Duck", shortcode: ":duck:", category: .animals, keywords: ["duck", "quack"], unicodeHex: "U+1F986"),
            EmojiItem(emoji: "🦉", name: "Owl", shortcode: ":owl:", category: .animals, keywords: ["owl", "night", "wise"], unicodeHex: "U+1F989"),
            EmojiItem(emoji: "🦇", name: "Bat", shortcode: ":bat:", category: .animals, keywords: ["bat", "vampire", "cave"], unicodeHex: "U+1F987"),
            EmojiItem(emoji: "🐺", name: "Wolf", shortcode: ":wolf:", category: .animals, keywords: ["wolf", "howl", "pack"], unicodeHex: "U+1F43A"),
            EmojiItem(emoji: "🦄", name: "Unicorn", shortcode: ":unicorn:", category: .animals, keywords: ["unicorn", "fantasy", "magic", "startup"], unicodeHex: "U+1F984"),
            EmojiItem(emoji: "🐝", name: "Honeybee", shortcode: ":bee:", category: .animals, keywords: ["bee", "honey", "insect"], unicodeHex: "U+1F41D"),
            EmojiItem(emoji: "🐛", name: "Bug", shortcode: ":bug:", category: .animals, keywords: ["bug", "insect", "caterpillar", "software defect"], unicodeHex: "U+1F41B"),
            EmojiItem(emoji: "🦋", name: "Butterfly", shortcode: ":butterfly:", category: .animals, keywords: ["butterfly", "pretty", "wings"], unicodeHex: "U+1F98B"),
            EmojiItem(emoji: "🐌", name: "Snail", shortcode: ":snail:", category: .animals, keywords: ["snail", "slow"], unicodeHex: "U+1F40C"),
            EmojiItem(emoji: "🐢", name: "Turtle", shortcode: ":turtle:", category: .animals, keywords: ["turtle", "tortoise", "slow"], unicodeHex: "U+1F422"),
            EmojiItem(emoji: "🐍", name: "Snake", shortcode: ":snake:", category: .animals, keywords: ["snake", "reptile", "python"], unicodeHex: "U+1F40D"),
            EmojiItem(emoji: "🐙", name: "Octopus", shortcode: ":octopus:", category: .animals, keywords: ["octopus", "sea", "ocean"], unicodeHex: "U+1F419"),
            EmojiItem(emoji: "🐬", name: "Dolphin", shortcode: ":dolphin:", category: .animals, keywords: ["dolphin", "ocean", "swim"], unicodeHex: "U+1F42C"),
            EmojiItem(emoji: "🐳", name: "Spouting Whale", shortcode: ":whale:", category: .animals, keywords: ["whale", "docker", "sea"], unicodeHex: "U+1F433"),
            EmojiItem(emoji: "🦈", name: "Shark", shortcode: ":shark:", category: .animals, keywords: ["shark", "sea", "predator"], unicodeHex: "U+1F988"),
            EmojiItem(emoji: "🦀", name: "Crab", shortcode: ":crab:", category: .animals, keywords: ["crab", "rust", "seafood", "beach"], unicodeHex: "U+1F980"),
            EmojiItem(emoji: "🌲", name: "Evergreen Tree", shortcode: ":evergreen_tree:", category: .animals, keywords: ["tree", "pine", "forest", "nature"], unicodeHex: "U+1F332"),
            EmojiItem(emoji: "🌳", name: "Deciduous Tree", shortcode: ":deciduous_tree:", category: .animals, keywords: ["tree", "nature", "green"], unicodeHex: "U+1F333"),
            EmojiItem(emoji: "🌴", name: "Palm Tree", shortcode: ":palm_tree:", category: .animals, keywords: ["palm", "tropical", "beach", "summer"], unicodeHex: "U+1F334"),
            EmojiItem(emoji: "🌵", name: "Cactus", shortcode: ":cactus:", category: .animals, keywords: ["cactus", "desert", "plant"], unicodeHex: "U+1F335"),
            EmojiItem(emoji: "🌱", name: "Seedling", shortcode: ":seedling:", category: .animals, keywords: ["plant", "sprout", "grow", "nature"], unicodeHex: "U+1F331"),
            EmojiItem(emoji: "🌿", name: "Herb", shortcode: ":herb:", category: .animals, keywords: ["plant", "leaf", "nature"], unicodeHex: "U+1F33F"),
            EmojiItem(emoji: "🍀", name: "Four Leaf Clover", shortcode: ":four_leaf_clover:", category: .animals, keywords: ["lucky", "clover", "irish"], unicodeHex: "U+1F340"),
            EmojiItem(emoji: "🌸", name: "Cherry Blossom", shortcode: ":cherry_blossom:", category: .animals, keywords: ["flower", "sakura", "pink", "japan"], unicodeHex: "U+1F338"),
            EmojiItem(emoji: "🌹", name: "Rose", shortcode: ":rose:", category: .animals, keywords: ["flower", "love", "red"], unicodeHex: "U+1F339"),
            EmojiItem(emoji: "🌻", name: "Sunflower", shortcode: ":sunflower:", category: .animals, keywords: ["flower", "yellow", "sun"], unicodeHex: "U+1F33B"),
            EmojiItem(emoji: "🔥", name: "Fire", shortcode: ":fire:", category: .animals, keywords: ["flame", "hot", "lit", "burn", "trend"], unicodeHex: "U+1F525"),
            EmojiItem(emoji: "✨", name: "Sparkles", shortcode: ":sparkles:", category: .animals, keywords: ["stars", "shine", "magic", "clean", "ai", "new"], unicodeHex: "U+2728"),
            EmojiItem(emoji: "⚡", name: "High Voltage", shortcode: ":zap:", category: .animals, keywords: ["lightning", "thunder", "power", "fast"], unicodeHex: "U+26A1"),
            EmojiItem(emoji: "🌈", name: "Rainbow", shortcode: ":rainbow:", category: .animals, keywords: ["color", "pride", "sky"], unicodeHex: "U+1F308"),
            EmojiItem(emoji: "☀️", name: "Sun", shortcode: ":sunny:", category: .animals, keywords: ["sun", "weather", "bright", "day"], unicodeHex: "U+2600"),
            EmojiItem(emoji: "🌙", name: "Crescent Moon", shortcode: ":crescent_moon:", category: .animals, keywords: ["moon", "night", "dark"], unicodeHex: "U+1F319"),
            EmojiItem(emoji: "⭐", name: "Star", shortcode: ":star:", category: .animals, keywords: ["star", "favorite", "yellow"], unicodeHex: "U+2B50"),

            // Food & Drink
            EmojiItem(emoji: "🍏", name: "Green Apple", shortcode: ":green_apple:", category: .food, keywords: ["fruit", "apple"], unicodeHex: "U+1F34F"),
            EmojiItem(emoji: "🍎", name: "Red Apple", shortcode: ":apple:", category: .food, keywords: ["fruit", "apple", "mac"], unicodeHex: "U+1F34E"),
            EmojiItem(emoji: "🍐", name: "Pear", shortcode: ":pear:", category: .food, keywords: ["fruit", "pear"], unicodeHex: "U+1F350"),
            EmojiItem(emoji: "🍊", name: "Tangerine", shortcode: ":tangerine:", category: .food, keywords: ["fruit", "orange", "citrus"], unicodeHex: "U+1F34A"),
            EmojiItem(emoji: "🍋", name: "Lemon", shortcode: ":lemon:", category: .food, keywords: ["fruit", "sour", "citrus"], unicodeHex: "U+1F34B"),
            EmojiItem(emoji: "🍌", name: "Banana", shortcode: ":banana:", category: .food, keywords: ["fruit", "banana", "potassium"], unicodeHex: "U+1F34C"),
            EmojiItem(emoji: "🍉", name: "Watermelon", shortcode: ":watermelon:", category: .food, keywords: ["fruit", "melon", "summer"], unicodeHex: "U+1F349"),
            EmojiItem(emoji: "🍇", name: "Grapes", shortcode: ":grapes:", category: .food, keywords: ["fruit", "wine", "grapes"], unicodeHex: "U+1F347"),
            EmojiItem(emoji: "🍓", name: "Strawberry", shortcode: ":strawberry:", category: .food, keywords: ["fruit", "berry", "sweet"], unicodeHex: "U+1F353"),
            EmojiItem(emoji: "🫐", name: "Blueberries", shortcode: ":blueberries:", category: .food, keywords: ["fruit", "berry"], unicodeHex: "U+1FAD0"),
            EmojiItem(emoji: "🍒", name: "Cherries", shortcode: ":cherries:", category: .food, keywords: ["fruit", "cherry"], unicodeHex: "U+1F352"),
            EmojiItem(emoji: "🍑", name: "Peach", shortcode: ":peach:", category: .food, keywords: ["fruit", "butt"], unicodeHex: "U+1F351"),
            EmojiItem(emoji: "🥭", name: "Mango", shortcode: ":mango:", category: .food, keywords: ["fruit", "tropical"], unicodeHex: "U+1F96D"),
            EmojiItem(emoji: "🍍", name: "Pineapple", shortcode: ":pineapple:", category: .food, keywords: ["fruit", "tropical"], unicodeHex: "U+1F34D"),
            EmojiItem(emoji: "🥥", name: "Coconut", shortcode: ":coconut:", category: .food, keywords: ["tropical", "nut"], unicodeHex: "U+1F965"),
            EmojiItem(emoji: "🥝", name: "Kiwi Fruit", shortcode: ":kiwi_fruit:", category: .food, keywords: ["fruit", "kiwi"], unicodeHex: "U+1F95D"),
            EmojiItem(emoji: "🍅", name: "Tomato", shortcode: ":tomato:", category: .food, keywords: ["vegetable", "red"], unicodeHex: "U+1F345"),
            EmojiItem(emoji: "🥑", name: "Avocado", shortcode: ":avocado:", category: .food, keywords: ["guacamole", "healthy"], unicodeHex: "U+1F951"),
            EmojiItem(emoji: "🍆", name: "Eggplant", shortcode: ":eggplant:", category: .food, keywords: ["aubergine", "vegetable"], unicodeHex: "U+1F346"),
            EmojiItem(emoji: "🥔", name: "Potato", shortcode: ":potato:", category: .food, keywords: ["potato", "spud"], unicodeHex: "U+1F954"),
            EmojiItem(emoji: "🥕", name: "Carrot", shortcode: ":carrot:", category: .food, keywords: ["vegetable", "orange"], unicodeHex: "U+1F955"),
            EmojiItem(emoji: "🌽", name: "Ear of Corn", shortcode: ":corn:", category: .food, keywords: ["corn", "maize"], unicodeHex: "U+1F33D"),
            EmojiItem(emoji: "🌶️", name: "Hot Pepper", shortcode: ":hot_pepper:", category: .food, keywords: ["spicy", "chili"], unicodeHex: "U+1F336"),
            EmojiItem(emoji: "🍞", name: "Bread", shortcode: ":bread:", category: .food, keywords: ["toast", "bakery", "carb"], unicodeHex: "U+1F35E"),
            EmojiItem(emoji: "🥐", name: "Croissant", shortcode: ":croissant:", category: .food, keywords: ["french", "pastry"], unicodeHex: "U+1F950"),
            EmojiItem(emoji: "🥖", name: "Baguette Bread", shortcode: ":baguette_bread:", category: .food, keywords: ["french", "bread"], unicodeHex: "U+1F956"),
            EmojiItem(emoji: "🧀", name: "Cheese Wedge", shortcode: ":cheese:", category: .food, keywords: ["cheese", "dairy"], unicodeHex: "U+1F9C0"),
            EmojiItem(emoji: "🍳", name: "Cooking", shortcode: ":egg:", category: .food, keywords: ["fried egg", "breakfast"], unicodeHex: "U+1F373"),
            EmojiItem(emoji: "🥞", name: "Pancakes", shortcode: ":pancakes:", category: .food, keywords: ["breakfast", "syrup"], unicodeHex: "U+1F95E"),
            EmojiItem(emoji: "🥓", name: "Bacon", shortcode: ":bacon:", category: .food, keywords: ["meat", "pork", "breakfast"], unicodeHex: "U+1F953"),
            EmojiItem(emoji: "🥩", name: "Cut of Meat", shortcode: ":meat_on_bone:", category: .food, keywords: ["steak", "beef"], unicodeHex: "U+1F969"),
            EmojiItem(emoji: "🍗", name: "Poultry Leg", shortcode: ":poultry_leg:", category: .food, keywords: ["chicken", "drumstick"], unicodeHex: "U+1F357"),
            EmojiItem(emoji: "🍔", name: "Hamburger", shortcode: ":hamburger:", category: .food, keywords: ["burger", "fast food", "beef"], unicodeHex: "U+1F354"),
            EmojiItem(emoji: "🍟", name: "French Fries", shortcode: ":fries:", category: .food, keywords: ["chips", "potato", "fast food"], unicodeHex: "U+1F35F"),
            EmojiItem(emoji: "🍕", name: "Pizza", shortcode: ":pizza:", category: .food, keywords: ["slice", "cheese", "italian"], unicodeHex: "U+1F355"),
            EmojiItem(emoji: "🌭", name: "Hot Dog", shortcode: ":hotdog:", category: .food, keywords: ["sausage", "frankfurter"], unicodeHex: "U+1F32D"),
            EmojiItem(emoji: "🥪", name: "Sandwich", shortcode: ":sandwich:", category: .food, keywords: ["bread", "lunch"], unicodeHex: "U+1F96A"),
            EmojiItem(emoji: "🌮", name: "Taco", shortcode: ":taco:", category: .food, keywords: ["mexican", "taco tuesday"], unicodeHex: "U+1F32E"),
            EmojiItem(emoji: "🌯", name: "Burrito", shortcode: ":burrito:", category: .food, keywords: ["mexican", "wrap"], unicodeHex: "U+1F32F"),
            EmojiItem(emoji: "🫔", name: "Tamale", shortcode: ":tamale:", category: .food, keywords: ["mexican", "food"], unicodeHex: "U+1FAD4"),
            EmojiItem(emoji: "🥗", name: "Green Salad", shortcode: ":green_salad:", category: .food, keywords: ["healthy", "salad", "diet"], unicodeHex: "U+1F957"),
            EmojiItem(emoji: "🍿", name: "Popcorn", shortcode: ":popcorn:", category: .food, keywords: ["movie", "snack"], unicodeHex: "U+1F37F"),
            EmojiItem(emoji: "🍝", name: "Spaghetti", shortcode: ":spaghetti:", category: .food, keywords: ["pasta", "italian", "noodles"], unicodeHex: "U+1F35D"),
            EmojiItem(emoji: "🍜", name: "Steaming Bowl", shortcode: ":ramen:", category: .food, keywords: ["ramen", "soup", "noodles", "japanese"], unicodeHex: "U+1F35C"),
            EmojiItem(emoji: "🍲", name: "Pot of Food", shortcode: ":stew:", category: .food, keywords: ["soup", "stew"], unicodeHex: "U+1F372"),
            EmojiItem(emoji: "🍛", name: "Curry Rice", shortcode: ":curry:", category: .food, keywords: ["curry", "indian", "japanese"], unicodeHex: "U+1F35B"),
            EmojiItem(emoji: "🍣", name: "Sushi", shortcode: ":sushi:", category: .food, keywords: ["fish", "rice", "japanese"], unicodeHex: "U+1F363"),
            EmojiItem(emoji: "🍱", name: "Bento Box", shortcode: ":bento:", category: .food, keywords: ["lunch", "japanese"], unicodeHex: "U+1F371"),
            EmojiItem(emoji: "🥟", name: "Dumpling", shortcode: ":dumpling:", category: .food, keywords: ["dim sum", "gyoza"], unicodeHex: "U+1F95F"),
            EmojiItem(emoji: "🍦", name: "Soft Ice Cream", shortcode: ":icecream:", category: .food, keywords: ["dessert", "cone", "vanilla"], unicodeHex: "U+1F366"),
            EmojiItem(emoji: "🍧", name: "Shaved Ice", shortcode: ":shaved_ice:", category: .food, keywords: ["dessert", "summer"], unicodeHex: "U+1F367"),
            EmojiItem(emoji: "🍨", name: "Ice Cream", shortcode: ":ice_cream:", category: .food, keywords: ["dessert", "gelato"], unicodeHex: "U+1F368"),
            EmojiItem(emoji: "🍩", name: "Doughnut", shortcode: ":doughnut:", category: .food, keywords: ["donut", "sweet"], unicodeHex: "U+1F369"),
            EmojiItem(emoji: "🍪", name: "Cookie", shortcode: ":cookie:", category: .food, keywords: ["biscuit", "chocolate chip", "snack"], unicodeHex: "U+1F36A"),
            EmojiItem(emoji: "🎂", name: "Birthday Cake", shortcode: ":birthday:", category: .food, keywords: ["cake", "celebration", "party"], unicodeHex: "U+1F382"),
            EmojiItem(emoji: "🍰", name: "Shortcake", shortcode: ":cake:", category: .food, keywords: ["dessert", "strawberry"], unicodeHex: "U+1F370"),
            EmojiItem(emoji: "🧁", name: "Cupcake", shortcode: ":cupcake:", category: .food, keywords: ["dessert", "frosting"], unicodeHex: "U+1F9C1"),
            EmojiItem(emoji: "🥧", name: "Pie", shortcode: ":pie:", category: .food, keywords: ["dessert", "pastry"], unicodeHex: "U+1F967"),
            EmojiItem(emoji: "🍫", name: "Chocolate Bar", shortcode: ":chocolate_bar:", category: .food, keywords: ["candy", "sweet", "cocoa"], unicodeHex: "U+1F36B"),
            EmojiItem(emoji: "🍬", name: "Candy", shortcode: ":candy:", category: .food, keywords: ["sweet", "lolly"], unicodeHex: "U+1F36C"),
            EmojiItem(emoji: "☕", name: "Hot Beverage", shortcode: ":coffee:", category: .food, keywords: ["coffee", "tea", "caffeine", "espresso", "morning"], unicodeHex: "U+2615"),
            EmojiItem(emoji: "🫖", name: "Teapot", shortcode: ":teapot:", category: .food, keywords: ["tea", "brew"], unicodeHex: "U+1FAD6"),
            EmojiItem(emoji: "🍵", name: "Teacup Without Handle", shortcode: ":tea:", category: .food, keywords: ["matcha", "green tea"], unicodeHex: "U+1F375"),
            EmojiItem(emoji: "🧃", name: "Beverage Box", shortcode: ":beverage_box:", category: .food, keywords: ["juice", "box"], unicodeHex: "U+1F9C3"),
            EmojiItem(emoji: "🥤", name: "Cup with Straw", shortcode: ":cup_with_straw:", category: .food, keywords: ["soda", "drink"], unicodeHex: "U+1F964"),
            EmojiItem(emoji: "🧋", name: "Bubble Tea", shortcode: ":bubble_tea:", category: .food, keywords: ["boba", "milk tea"], unicodeHex: "U+1F9CB"),
            EmojiItem(emoji: "🍺", name: "Beer Mug", shortcode: ":beer:", category: .food, keywords: ["alcohol", "brew", "pub"], unicodeHex: "U+1F37A"),
            EmojiItem(emoji: "🍻", name: "Clinking Beer Mugs", shortcode: ":beers:", category: .food, keywords: ["cheers", "toast", "party"], unicodeHex: "U+1F37B"),
            EmojiItem(emoji: "🍷", name: "Wine Glass", shortcode: ":wine_glass:", category: .food, keywords: ["wine", "red wine", "alcohol"], unicodeHex: "U+1F377"),
            EmojiItem(emoji: "🍸", name: "Cocktail Glass", shortcode: ":cocktail:", category: .food, keywords: ["martini", "drink", "bar"], unicodeHex: "U+1F378"),
            EmojiItem(emoji: "🍹", name: "Tropical Drink", shortcode: ":tropical_drink:", category: .food, keywords: ["cocktail", "vacation"], unicodeHex: "U+1F379"),
            EmojiItem(emoji: "🍾", name: "Bottle with Popping Cork", shortcode: ":champagne:", category: .food, keywords: ["champagne", "celebrate"], unicodeHex: "U+1F37E"),

            // Travel & Places
            EmojiItem(emoji: "🚗", name: "Automobile", shortcode: ":car:", category: .travel, keywords: ["car", "vehicle", "drive"], unicodeHex: "U+1F697"),
            EmojiItem(emoji: "🚕", name: "Taxi", shortcode: ":taxi:", category: .travel, keywords: ["cab", "uber", "yellow cab"], unicodeHex: "U+1F695"),
            EmojiItem(emoji: "🚙", name: "Sport Utility Vehicle", shortcode: ":blue_car:", category: .travel, keywords: ["suv", "car"], unicodeHex: "U+1F699"),
            EmojiItem(emoji: "🚌", name: "Bus", shortcode: ":bus:", category: .travel, keywords: ["transit", "transport"], unicodeHex: "U+1F68C"),
            EmojiItem(emoji: "🏎️", name: "Racing Car", shortcode: ":racing_car:", category: .travel, keywords: ["f1", "fast", "race"], unicodeHex: "U+1F3CE"),
            EmojiItem(emoji: "🚓", name: "Police Car", shortcode: ":police_car:", category: .travel, keywords: ["cops", "emergency"], unicodeHex: "U+1F693"),
            EmojiItem(emoji: "🚑", name: "Ambulance", shortcode: ":ambulance:", category: .travel, keywords: ["hospital", "emergency"], unicodeHex: "U+1F691"),
            EmojiItem(emoji: "🚒", name: "Fire Engine", shortcode: ":fire_engine:", category: .travel, keywords: ["fire truck", "emergency"], unicodeHex: "U+1F692"),
            EmojiItem(emoji: "🚚", name: "Delivery Truck", shortcode: ":truck:", category: .travel, keywords: ["cargo", "shipping"], unicodeHex: "U+1F69A"),
            EmojiItem(emoji: "🚛", name: "Articulated Lorry", shortcode: ":articulated_lorry:", category: .travel, keywords: ["semi", "truck"], unicodeHex: "U+1F69B"),
            EmojiItem(emoji: "🚜", name: "Tractor", shortcode: ":tractor:", category: .travel, keywords: ["farm", "agriculture"], unicodeHex: "U+1F69C"),
            EmojiItem(emoji: "🛴", name: "Kick Scooter", shortcode: ":kick_scooter:", category: .travel, keywords: ["scooter", "ride"], unicodeHex: "U+1F6F4"),
            EmojiItem(emoji: "🚲", name: "Bicycle", shortcode: ":bike:", category: .travel, keywords: ["bike", "cycling"], unicodeHex: "U+1F6B2"),
            EmojiItem(emoji: "🛵", name: "Motor Scooter", shortcode: ":motor_scooter:", category: .travel, keywords: ["vespa", "moped"], unicodeHex: "U+1F6F5"),
            EmojiItem(emoji: "🏍️", name: "Motorcycle", shortcode: ":motorcycle:", category: .travel, keywords: ["bike", "harley"], unicodeHex: "U+1F3CD"),
            EmojiItem(emoji: "🚨", name: "Police Car Light", shortcode: ":rotating_light:", category: .travel, keywords: ["alert", "warning", "emergency", "siren"], unicodeHex: "U+1F6A8"),
            EmojiItem(emoji: "🚆", name: "Train", shortcode: ":train2:", category: .travel, keywords: ["rail", "transit", "subway"], unicodeHex: "U+1F686"),
            EmojiItem(emoji: "🚇", name: "Metro", shortcode: ":metro:", category: .travel, keywords: ["subway", "underground"], unicodeHex: "U+1F687"),
            EmojiItem(emoji: "🚄", name: "High-Speed Train", shortcode: ":bullettrain_side:", category: .travel, keywords: ["shinkansen", "fast"], unicodeHex: "U+1F684"),
            EmojiItem(emoji: "✈️", name: "Airplane", shortcode: ":airplane:", category: .travel, keywords: ["flight", "travel", "fly", "trip"], unicodeHex: "U+2708"),
            EmojiItem(emoji: "🛫", name: "Airplane Departure", shortcode: ":flight_departure:", category: .travel, keywords: ["takeoff", "leave"], unicodeHex: "U+1F6EB"),
            EmojiItem(emoji: "🛬", name: "Airplane Arrival", shortcode: ":flight_arrival:", category: .travel, keywords: ["landing", "arrive"], unicodeHex: "U+1F6EC"),
            EmojiItem(emoji: "🚀", name: "Rocket", shortcode: ":rocket:", category: .travel, keywords: ["space", "launch", "fast", "moon", "speed"], unicodeHex: "U+1F680"),
            EmojiItem(emoji: "🛸", name: "Flying Saucer", shortcode: ":flying_saucer:", category: .travel, keywords: ["ufo", "alien"], unicodeHex: "U+1F6F8"),
            EmojiItem(emoji: "🚁", name: "Helicopter", shortcode: ":helicopter:", category: .travel, keywords: ["chopper", "fly"], unicodeHex: "U+1F681"),
            EmojiItem(emoji: "⛵", name: "Sailboat", shortcode: ":sailboat:", category: .travel, keywords: ["boat", "sea", "sailing"], unicodeHex: "U+26F5"),
            EmojiItem(emoji: "🚤", name: "Speedboat", shortcode: ":speedboat:", category: .travel, keywords: ["fast boat", "ocean"], unicodeHex: "U+1F6A4"),
            EmojiItem(emoji: "🛳️", name: "Passenger Ship", shortcode: ":passenger_ship:", category: .travel, keywords: ["cruise", "vacation"], unicodeHex: "U+1F6F3"),
            EmojiItem(emoji: "⚓", name: "Anchor", shortcode: ":anchor:", category: .travel, keywords: ["ship", "harbor", "navy"], unicodeHex: "U+2693"),
            EmojiItem(emoji: "🗺️", name: "World Map", shortcode: ":world_map:", category: .travel, keywords: ["travel", "geography", "navigation"], unicodeHex: "U+1F5FA"),
            EmojiItem(emoji: "🗽", name: "Statue of Liberty", shortcode: ":statue_of_liberty:", category: .travel, keywords: ["new york", "usa"], unicodeHex: "U+1F5FD"),
            EmojiItem(emoji: "🗼", name: "Tokyo Tower", shortcode: ":tokyo_tower:", category: .travel, keywords: ["japan", "tokyo"], unicodeHex: "U+1F5FC"),
            EmojiItem(emoji: "🏰", name: "Castle", shortcode: ":european_castle:", category: .travel, keywords: ["disney", "fairy tale"], unicodeHex: "U+1F3F0"),
            EmojiItem(emoji: "⛰️", name: "Mountain", shortcode: ":mountain:", category: .travel, keywords: ["hike", "nature", "climb"], unicodeHex: "U+26F0"),
            EmojiItem(emoji: "🏖️", name: "Beach with Umbrella", shortcode: ":beach_umbrella:", category: .travel, keywords: ["summer", "vacation", "ocean"], unicodeHex: "U+1F3D6"),
            EmojiItem(emoji: "🏕️", name: "Camping", shortcode: ":camping:", category: .travel, keywords: ["tent", "outdoors"], unicodeHex: "U+1F3D5"),

            // Activities
            EmojiItem(emoji: "⚽", name: "Soccer Ball", shortcode: ":soccer:", category: .activities, keywords: ["football", "fifa", "sport"], unicodeHex: "U+26BD"),
            EmojiItem(emoji: "🏀", name: "Basketball", shortcode: ":basketball:", category: .activities, keywords: ["nba", "sport", "hoop"], unicodeHex: "U+1F3C0"),
            EmojiItem(emoji: "🏈", name: "American Football", shortcode: ":football:", category: .activities, keywords: ["nfl", "superbowl"], unicodeHex: "U+1F3C8"),
            EmojiItem(emoji: "⚾", name: "Baseball", shortcode: ":baseball:", category: .activities, keywords: ["mlb", "sport"], unicodeHex: "U+26BE"),
            EmojiItem(emoji: "🎾", name: "Tennis", shortcode: ":tennis:", category: .activities, keywords: ["sport", "court"], unicodeHex: "U+1F3BE"),
            EmojiItem(emoji: "🏐", name: "Volleyball", shortcode: ":volleyball:", category: .activities, keywords: ["sport", "beach"], unicodeHex: "U+1F3D0"),
            EmojiItem(emoji: "🏉", name: "Rugby Football", shortcode: ":rugby_football:", category: .activities, keywords: ["sport", "rugby"], unicodeHex: "U+1F3C9"),
            EmojiItem(emoji: "🎱", name: "Pool 8 Ball", shortcode: ":8ball:", category: .activities, keywords: ["billiards", "magic 8 ball", "game"], unicodeHex: "U+1F3B1"),
            EmojiItem(emoji: "🏓", name: "Ping Pong", shortcode: ":ping_pong:", category: .activities, keywords: ["table tennis", "paddle"], unicodeHex: "U+1F3D3"),
            EmojiItem(emoji: "🏸", name: "Badminton", shortcode: ":badminton:", category: .activities, keywords: ["shuttlecock", "sport"], unicodeHex: "U+1F3F8"),
            EmojiItem(emoji: "🥊", name: "Boxing Glove", shortcode: ":boxing_glove:", category: .activities, keywords: ["fight", "punch"], unicodeHex: "U+1F94A"),
            EmojiItem(emoji: "🥋", name: "Martial Arts Uniform", shortcode: ":martial_arts_uniform:", category: .activities, keywords: ["karate", "judo"], unicodeHex: "U+1F94B"),
            EmojiItem(emoji: "⛳", name: "Flag in Hole", shortcode: ":golf:", category: .activities, keywords: ["golf", "putt"], unicodeHex: "U+26F3"),
            EmojiItem(emoji: "⛸️", name: "Ice Skate", shortcode: ":ice_skate:", category: .activities, keywords: ["skating", "winter"], unicodeHex: "U+26F8"),
            EmojiItem(emoji: "🛹", name: "Skateboard", shortcode: ":skateboard:", category: .activities, keywords: ["skate", "board"], unicodeHex: "U+1F6F9"),
            EmojiItem(emoji: "🏋️", name: "Person Lifting Weights", shortcode: ":weight_lifting:", category: .activities, keywords: ["gym", "workout", "fitness"], unicodeHex: "U+1F3CB"),
            EmojiItem(emoji: "🧘", name: "Person in Lotus Position", shortcode: ":lotus_position:", category: .activities, keywords: ["yoga", "meditation", "zen"], unicodeHex: "U+1F9D8"),
            EmojiItem(emoji: "🎯", name: "Bullseye", shortcode: ":dart:", category: .activities, keywords: ["target", "accuracy", "bullseye", "goal"], unicodeHex: "U+1F3AF"),
            EmojiItem(emoji: "🎮", name: "Video Game", shortcode: ":video_game:", category: .activities, keywords: ["game", "playstation", "xbox", "controller", "gaming"], unicodeHex: "U+1F3AE"),
            EmojiItem(emoji: "🎲", name: "Game Die", shortcode: ":game_die:", category: .activities, keywords: ["dice", "random", "board game"], unicodeHex: "U+1F3B2"),
            EmojiItem(emoji: "🧩", name: "Puzzle Piece", shortcode: ":puzzle_piece:", category: .activities, keywords: ["puzzle", "jigsaw", "logic"], unicodeHex: "U+1F9E9"),
            EmojiItem(emoji: "🎨", name: "Artist Palette", shortcode: ":art:", category: .activities, keywords: ["paint", "art", "design", "creative"], unicodeHex: "U+1F3A8"),
            EmojiItem(emoji: "🎭", name: "Performing Arts", shortcode: ":performing_arts:", category: .activities, keywords: ["theater", "drama", "acting"], unicodeHex: "U+1F3AD"),
            EmojiItem(emoji: "🎤", name: "Microphone", shortcode: ":microphone:", category: .activities, keywords: ["sing", "karaoke", "podcast"], unicodeHex: "U+1F3A4"),
            EmojiItem(emoji: "🎧", name: "Headphone", shortcode: ":headphones:", category: .activities, keywords: ["music", "audio", "listen"], unicodeHex: "U+1F3A7"),
            EmojiItem(emoji: "🎷", name: "Saxophone", shortcode: ":saxophone:", category: .activities, keywords: ["jazz", "music", "instrument"], unicodeHex: "U+1F3B7"),
            EmojiItem(emoji: "🎸", name: "Guitar", shortcode: ":guitar:", category: .activities, keywords: ["rock", "music", "instrument"], unicodeHex: "U+1F3B8"),
            EmojiItem(emoji: "🎹", name: "Musical Keyboard", shortcode: ":musical_keyboard:", category: .activities, keywords: ["piano", "music"], unicodeHex: "U+1F3B9"),
            EmojiItem(emoji: "🥁", name: "Drum", shortcode: ":drum:", category: .activities, keywords: ["beat", "music"], unicodeHex: "U+1F941"),
            EmojiItem(emoji: "🏆", name: "Trophy", shortcode: ":trophy:", category: .activities, keywords: ["winner", "first place", "champion", "award"], unicodeHex: "U+1F3C6"),
            EmojiItem(emoji: "🥇", name: "1st Place Medal", shortcode: ":first_place_medal:", category: .activities, keywords: ["gold", "winner", "first"], unicodeHex: "U+1F947"),
            EmojiItem(emoji: "🥈", name: "2nd Place Medal", shortcode: ":second_place_medal:", category: .activities, keywords: ["silver", "second"], unicodeHex: "U+1F948"),
            EmojiItem(emoji: "🥉", name: "3rd Place Medal", shortcode: ":third_place_medal:", category: .activities, keywords: ["bronze", "third"], unicodeHex: "U+1F949"),
            EmojiItem(emoji: "🎖️", name: "Military Medal", shortcode: ":military_medal:", category: .activities, keywords: ["honor", "award"], unicodeHex: "U+1F396"),
            EmojiItem(emoji: "🎉", name: "Party Popper", shortcode: ":tada:", category: .activities, keywords: ["celebration", "party", "congratulations", "hooray"], unicodeHex: "U+1F389"),
            EmojiItem(emoji: "🎊", name: "Confetti Ball", shortcode: ":confetti_ball:", category: .activities, keywords: ["party", "celebration"], unicodeHex: "U+1F38A"),

            // Objects
            EmojiItem(emoji: "📱", name: "Mobile Phone", shortcode: ":iphone:", category: .objects, keywords: ["iphone", "smartphone", "cell"], unicodeHex: "U+1F4F1"),
            EmojiItem(emoji: "💻", name: "Laptop", shortcode: ":computer:", category: .objects, keywords: ["macbook", "pc", "tech", "code", "developer"], unicodeHex: "U+1F4BB"),
            EmojiItem(emoji: "🖥️", name: "Desktop Computer", shortcode: ":desktop_computer:", category: .objects, keywords: ["imac", "monitor", "pc"], unicodeHex: "U+1F5A5"),
            EmojiItem(emoji: "⌨️", name: "Keyboard", shortcode: ":keyboard:", category: .objects, keywords: ["typing", "mechanical keyboard"], unicodeHex: "U+2328"),
            EmojiItem(emoji: "🖱️", name: "Computer Mouse", shortcode: ":computer_mouse:", category: .objects, keywords: ["click", "trackpad"], unicodeHex: "U+1F5B1"),
            EmojiItem(emoji: "💾", name: "Floppy Disk", shortcode: ":floppy_disk:", category: .objects, keywords: ["save", "retro", "disk"], unicodeHex: "U+1F4BE"),
            EmojiItem(emoji: "💿", name: "Optical Disk", shortcode: ":cd:", category: .objects, keywords: ["cd", "dvd", "music"], unicodeHex: "U+1F4BF"),
            EmojiItem(emoji: "📷", name: "Camera", shortcode: ":camera:", category: .objects, keywords: ["photo", "picture", "shoot"], unicodeHex: "U+1F4F7"),
            EmojiItem(emoji: "🎥", name: "Movie Camera", shortcode: ":movie_camera:", category: .objects, keywords: ["film", "video", "cinema"], unicodeHex: "U+1F3A5"),
            EmojiItem(emoji: "📽️", name: "Film Projector", shortcode: ":film_projector:", category: .objects, keywords: ["cinema", "movie"], unicodeHex: "U+1F4FD"),
            EmojiItem(emoji: "🔍", name: "Magnifying Glass Tilted Left", shortcode: ":mag:", category: .objects, keywords: ["search", "find", "explore", "query"], unicodeHex: "U+1F50D"),
            EmojiItem(emoji: "🔎", name: "Magnifying Glass Tilted Right", shortcode: ":mag_right:", category: .objects, keywords: ["search", "find"], unicodeHex: "U+1F50E"),
            EmojiItem(emoji: "🕯️", name: "Candle", shortcode: ":candle:", category: .objects, keywords: ["light", "wax", "flame"], unicodeHex: "U+1F56F"),
            EmojiItem(emoji: "💡", name: "Light Bulb", shortcode: ":bulb:", category: .objects, keywords: ["idea", "bright", "electricity", "smart", "innovation"], unicodeHex: "U+1F4A1"),
            EmojiItem(emoji: "🔦", name: "Flashlight", shortcode: ":flashlight:", category: .objects, keywords: ["torch", "light"], unicodeHex: "U+1F526"),
            EmojiItem(emoji: "📖", name: "Open Book", shortcode: ":book:", category: .objects, keywords: ["read", "library", "study", "docs"], unicodeHex: "U+1F4D6"),
            EmojiItem(emoji: "📚", name: "Books", shortcode: ":books:", category: .objects, keywords: ["library", "study", "reading", "education"], unicodeHex: "U+1F4DA"),
            EmojiItem(emoji: "🏷️", name: "Label", shortcode: ":label:", category: .objects, keywords: ["tag", "price"], unicodeHex: "U+1F3F7"),
            EmojiItem(emoji: "💰", name: "Money Bag", shortcode: ":moneybag:", category: .objects, keywords: ["cash", "dollar", "wealth", "rich"], unicodeHex: "U+1F4B0"),
            EmojiItem(emoji: "🪙", name: "Coin", shortcode: ":coin:", category: .objects, keywords: ["currency", "crypto", "gold"], unicodeHex: "U+1FA99"),
            EmojiItem(emoji: "💳", name: "Credit Card", shortcode: ":credit_card:", category: .objects, keywords: ["payment", "visa", "mastercard"], unicodeHex: "U+1F4B3"),
            EmojiItem(emoji: "💎", name: "Gem Stone", shortcode: ":gem:", category: .objects, keywords: ["diamond", "jewel", "precious", "ruby"], unicodeHex: "U+1F48E"),
            EmojiItem(emoji: "📦", name: "Package", shortcode: ":package:", category: .objects, keywords: ["box", "delivery", "shipping", "parcel", "npm"], unicodeHex: "U+1F4E6"),
            EmojiItem(emoji: "📫", name: "Closed Mailbox with Raised Flag", shortcode: ":mailbox:", category: .objects, keywords: ["mail", "post", "inbox"], unicodeHex: "U+1F4EB"),
            EmojiItem(emoji: "📝", name: "Memo", shortcode: ":memo:", category: .objects, keywords: ["note", "write", "document", "pencil"], unicodeHex: "U+1F4DD"),
            EmojiItem(emoji: "📁", name: "File Folder", shortcode: ":file_folder:", category: .objects, keywords: ["directory", "folder", "documents"], unicodeHex: "U+1F4C1"),
            EmojiItem(emoji: "📂", name: "Open File Folder", shortcode: ":open_file_folder:", category: .objects, keywords: ["folder", "open", "files"], unicodeHex: "U+1F4C2"),
            EmojiItem(emoji: "📅", name: "Calendar", shortcode: ":calendar:", category: .objects, keywords: ["date", "schedule", "events"], unicodeHex: "U+1F4C5"),
            EmojiItem(emoji: "📊", name: "Bar Chart", shortcode: ":bar_chart:", category: .objects, keywords: ["stats", "graph", "analytics", "metrics"], unicodeHex: "U+1F4CA"),
            EmojiItem(emoji: "📈", name: "Chart Increasing", shortcode: ":chart_with_upwards_trend:", category: .objects, keywords: ["growth", "stonks", "profit", "metrics"], unicodeHex: "U+1F4C8"),
            EmojiItem(emoji: "📉", name: "Chart Decreasing", shortcode: ":chart_with_downwards_trend:", category: .objects, keywords: ["loss", "drop", "metrics"], unicodeHex: "U+1F4C9"),
            EmojiItem(emoji: "📌", name: "Pushpin", shortcode: ":pushpin:", category: .objects, keywords: ["pin", "location", "mark", "sticky"], unicodeHex: "U+1F4CC"),
            EmojiItem(emoji: "📍", name: "Round Pushpin", shortcode: ":round_pushpin:", category: .objects, keywords: ["location", "map", "pin"], unicodeHex: "U+1F4CD"),
            EmojiItem(emoji: "📎", name: "Paperclip", shortcode: ":paperclip:", category: .objects, keywords: ["attach", "attachment", "document"], unicodeHex: "U+1F4CE"),
            EmojiItem(emoji: "✂️", name: "Scissors", shortcode: ":scissors:", category: .objects, keywords: ["cut", "snip"], unicodeHex: "U+2702"),
            EmojiItem(emoji: "🔒", name: "Locked", shortcode: ":lock:", category: .objects, keywords: ["security", "secure", "private", "password"], unicodeHex: "U+1F512"),
            EmojiItem(emoji: "🔓", name: "Unlocked", shortcode: ":unlock:", category: .objects, keywords: ["open", "insecure"], unicodeHex: "U+1F513"),
            EmojiItem(emoji: "🔑", name: "Key", shortcode: ":key:", category: .objects, keywords: ["password", "auth", "access"], unicodeHex: "U+1F511"),
            EmojiItem(emoji: "🔨", name: "Hammer", shortcode: ":hammer:", category: .objects, keywords: ["build", "tool", "fix"], unicodeHex: "U+1F528"),
            EmojiItem(emoji: "🪛", name: "Screwdriver", shortcode: ":screwdriver:", category: .objects, keywords: ["tool", "repair"], unicodeHex: "U+1FA9B"),
            EmojiItem(emoji: "🔧", name: "Wrench", shortcode: ":wrench:", category: .objects, keywords: ["tool", "settings", "repair", "config"], unicodeHex: "U+1F527"),
            EmojiItem(emoji: "⚙️", name: "Gear", shortcode: ":gear:", category: .objects, keywords: ["settings", "preferences", "config", "options"], unicodeHex: "U+2699"),
            EmojiItem(emoji: "🧱", name: "Brick", shortcode: ":brick:", category: .objects, keywords: ["build", "wall"], unicodeHex: "U+1F9F1"),
            EmojiItem(emoji: "🧪", name: "Test Tube", shortcode: ":test_tube:", category: .objects, keywords: ["science", "chemistry", "experiment", "test"], unicodeHex: "U+1F9EA"),
            EmojiItem(emoji: "🧲", name: "Magnet", shortcode: ":magnet:", category: .objects, keywords: ["attract", "magnetic"], unicodeHex: "U+1F9F2"),

            // Symbols
            EmojiItem(emoji: "❤️", name: "Red Heart", shortcode: ":heart:", category: .symbols, keywords: ["love", "like", "heart", "valentine"], unicodeHex: "U+2764"),
            EmojiItem(emoji: "🧡", name: "Orange Heart", shortcode: ":orange_heart:", category: .symbols, keywords: ["love", "orange"], unicodeHex: "U+1F9E1"),
            EmojiItem(emoji: "💛", name: "Yellow Heart", shortcode: ":yellow_heart:", category: .symbols, keywords: ["love", "yellow", "friendship"], unicodeHex: "U+1F49B"),
            EmojiItem(emoji: "💚", name: "Green Heart", shortcode: ":green_heart:", category: .symbols, keywords: ["love", "green", "nature"], unicodeHex: "U+1F49A"),
            EmojiItem(emoji: "💙", name: "Blue Heart", shortcode: ":blue_heart:", category: .symbols, keywords: ["love", "blue"], unicodeHex: "U+1F499"),
            EmojiItem(emoji: "💜", name: "Purple Heart", shortcode: ":purple_heart:", category: .symbols, keywords: ["love", "purple"], unicodeHex: "U+1F49C"),
            EmojiItem(emoji: "🖤", name: "Black Heart", shortcode: ":black_heart:", category: .symbols, keywords: ["love", "black", "dark"], unicodeHex: "U+1F5A4"),
            EmojiItem(emoji: "🤍", name: "White Heart", shortcode: ":white_heart:", category: .symbols, keywords: ["love", "white", "pure"], unicodeHex: "U+1F90D"),
            EmojiItem(emoji: "💔", name: "Broken Heart", shortcode: ":broken_heart:", category: .symbols, keywords: ["breakup", "sad", "heartbreak"], unicodeHex: "U+1F494"),
            EmojiItem(emoji: "💯", name: "Hundred Points", shortcode: ":100:", category: .symbols, keywords: ["perfect", "score", "keep it 100", "full"], unicodeHex: "U+1F4AF"),
            EmojiItem(emoji: "💢", name: "Anger Symbol", shortcode: ":anger:", category: .symbols, keywords: ["angry", "mad", "anime"], unicodeHex: "U+1F4A2"),
            EmojiItem(emoji: "💬", name: "Speech Balloon", shortcode: ":speech_balloon:", category: .symbols, keywords: ["comment", "message", "chat"], unicodeHex: "U+1F4AC"),
            EmojiItem(emoji: "🗯️", name: "Right Anger Bubble", shortcode: ":anger_bubble:", category: .symbols, keywords: ["shout", "mad"], unicodeHex: "U+1F5E8"),
            EmojiItem(emoji: "💭", name: "Thought Balloon", shortcode: ":thought_balloon:", category: .symbols, keywords: ["think", "idea", "dream"], unicodeHex: "U+1F4AD"),
            EmojiItem(emoji: "💤", name: "Zzz", shortcode: ":zzz:", category: .symbols, keywords: ["sleep", "tired", "snore"], unicodeHex: "U+1F4A4"),
            EmojiItem(emoji: "🛑", name: "Stop Sign", shortcode: ":stop_sign:", category: .symbols, keywords: ["stop", "halt", "red"], unicodeHex: "U+1F6D1"),
            EmojiItem(emoji: "⛔", name: "No Entry", shortcode: ":no_entry:", category: .symbols, keywords: ["forbidden", "restricted"], unicodeHex: "U+26D4"),
            EmojiItem(emoji: "🚫", name: "Prohibited", shortcode: ":no_entry_sign:", category: .symbols, keywords: ["banned", "no"], unicodeHex: "U+1F6AB"),
            EmojiItem(emoji: "⚠️", name: "Warning", shortcode: ":warning:", category: .symbols, keywords: ["caution", "alert", "danger"], unicodeHex: "U+26A0"),
            EmojiItem(emoji: "☢️", name: "Radioactive", shortcode: ":radioactive:", category: .symbols, keywords: ["hazard", "nuclear"], unicodeHex: "U+2622"),
            EmojiItem(emoji: "☣️", name: "Biohazard", shortcode: ":biohazard:", category: .symbols, keywords: ["hazard", "virus", "danger"], unicodeHex: "U+2623"),
            EmojiItem(emoji: "⬆️", name: "Up Arrow", shortcode: ":arrow_up:", category: .symbols, keywords: ["up", "direction"], unicodeHex: "U+2B06"),
            EmojiItem(emoji: "↗️", name: "Up-Right Arrow", shortcode: ":arrow_upper_right:", category: .symbols, keywords: ["northeast", "direction"], unicodeHex: "U+2197"),
            EmojiItem(emoji: "➡️", name: "Right Arrow", shortcode: ":arrow_right:", category: .symbols, keywords: ["right", "next", "direction"], unicodeHex: "U+27A1"),
            EmojiItem(emoji: "↘️", name: "Down-Right Arrow", shortcode: ":arrow_lower_right:", category: .symbols, keywords: ["southeast", "direction"], unicodeHex: "U+2198"),
            EmojiItem(emoji: "⬇️", name: "Down Arrow", shortcode: ":arrow_down:", category: .symbols, keywords: ["down", "direction"], unicodeHex: "U+2B07"),
            EmojiItem(emoji: "↙️", name: "Down-Left Arrow", shortcode: ":arrow_lower_left:", category: .symbols, keywords: ["southwest", "direction"], unicodeHex: "U+2199"),
            EmojiItem(emoji: "⬅️", name: "Left Arrow", shortcode: ":arrow_left:", category: .symbols, keywords: ["left", "back", "direction"], unicodeHex: "U+2B05"),
            EmojiItem(emoji: "↖️", name: "Up-Left Arrow", shortcode: ":arrow_upper_left:", category: .symbols, keywords: ["northwest", "direction"], unicodeHex: "U+2196"),
            EmojiItem(emoji: "🔄", name: "Counterclockwise Arrows Button", shortcode: ":arrows_counterclockwise:", category: .symbols, keywords: ["sync", "reload", "refresh", "rotate"], unicodeHex: "U+1F504"),
            EmojiItem(emoji: "✅", name: "Check Mark Button", shortcode: ":white_check_mark:", category: .symbols, keywords: ["done", "correct", "success", "pass", "ok"], unicodeHex: "U+2705"),
            EmojiItem(emoji: "❌", name: "Cross Mark", shortcode: ":x:", category: .symbols, keywords: ["error", "no", "wrong", "fail", "cancel"], unicodeHex: "U+274C"),
            EmojiItem(emoji: "❎", name: "Cross Mark Button", shortcode: ":negative_squared_cross_mark:", category: .symbols, keywords: ["cancel", "delete"], unicodeHex: "U+274E"),
            EmojiItem(emoji: "➕", name: "Plus", shortcode: ":heavy_plus_sign:", category: .symbols, keywords: ["add", "math"], unicodeHex: "U+2795"),
            EmojiItem(emoji: "➖", name: "Minus", shortcode: ":heavy_minus_sign:", category: .symbols, keywords: ["subtract", "math"], unicodeHex: "U+2796"),
            EmojiItem(emoji: "✖️", name: "Multiply", shortcode: ":heavy_multiplication_x:", category: .symbols, keywords: ["times", "math"], unicodeHex: "U+2716"),
            EmojiItem(emoji: "➗", name: "Divide", shortcode: ":heavy_division_sign:", category: .symbols, keywords: ["divide", "math"], unicodeHex: "U+2797"),
            EmojiItem(emoji: "♾️", name: "Infinity", shortcode: ":infinity:", category: .symbols, keywords: ["forever", "loop"], unicodeHex: "U+267E"),
            EmojiItem(emoji: "❓", name: "Question Mark", shortcode: ":question:", category: .symbols, keywords: ["help", "what", "unknown", "query"], unicodeHex: "U+2753"),
            EmojiItem(emoji: "❗", name: "Exclamation Mark", shortcode: ":exclamation:", category: .symbols, keywords: ["important", "alert", "attention", "bang"], unicodeHex: "U+2757"),
            EmojiItem(emoji: "🔔", name: "Bell", shortcode: ":bell:", category: .symbols, keywords: ["notification", "sound", "ring"], unicodeHex: "U+1F514"),
            EmojiItem(emoji: "🔕", name: "Bell with Slash", shortcode: ":no_bell:", category: .symbols, keywords: ["mute", "silent", "quiet"], unicodeHex: "U+1F515"),

            // Flags
            EmojiItem(emoji: "🏁", name: "Chequered Flag", shortcode: ":checkered_flag:", category: .flags, keywords: ["race", "finish", "winner"], unicodeHex: "U+1F3C1"),
            EmojiItem(emoji: "🚩", name: "Triangular Flag", shortcode: ":triangular_flag_on_post:", category: .flags, keywords: ["red flag", "warning", "location"], unicodeHex: "U+1F6A9"),
            EmojiItem(emoji: "🎌", name: "Crossed Flags", shortcode: ":crossed_flags:", category: .flags, keywords: ["japan", "celebrate"], unicodeHex: "U+1F38C"),
            EmojiItem(emoji: "🏴‍☠️", name: "Pirate Flag", shortcode: ":pirate_flag:", category: .flags, keywords: ["skull", "crossbones", "jolly roger"], unicodeHex: "U+1F3F4-200D-2620"),
            EmojiItem(emoji: "🇺🇸", name: "Flag: United States", shortcode: ":us:", category: .flags, keywords: ["america", "usa"], unicodeHex: "U+1F1FA-1F1F8"),
            EmojiItem(emoji: "🇬🇧", name: "Flag: United Kingdom", shortcode: ":uk:", category: .flags, keywords: ["britain", "uk", "great britain"], unicodeHex: "U+1F1EC-1F1E7"),
            EmojiItem(emoji: "🇯🇵", name: "Flag: Japan", shortcode: ":jp:", category: .flags, keywords: ["japan", "nihon"], unicodeHex: "U+1F1EF-1F1F5"),
            EmojiItem(emoji: "🇩🇪", name: "Flag: Germany", shortcode: ":de:", category: .flags, keywords: ["germany", "deutschland"], unicodeHex: "U+1F1E9-1F1EA"),
            EmojiItem(emoji: "🇫🇷", name: "Flag: France", shortcode: ":fr:", category: .flags, keywords: ["france", "french"], unicodeHex: "U+1F1EB-1F1F7"),
            EmojiItem(emoji: "🇮🇩", name: "Flag: Indonesia", shortcode: ":id:", category: .flags, keywords: ["indonesia"], unicodeHex: "U+1F1EE-1F1E9"),
            EmojiItem(emoji: "🇨🇦", name: "Flag: Canada", shortcode: ":ca:", category: .flags, keywords: ["canada"], unicodeHex: "U+1F1E8-1F1E6"),
            EmojiItem(emoji: "🇦🇺", name: "Flag: Australia", shortcode: ":au:", category: .flags, keywords: ["australia"], unicodeHex: "U+1F1E6-1F1FA"),
            EmojiItem(emoji: "🇰🇷", name: "Flag: South Korea", shortcode: ":kr:", category: .flags, keywords: ["korea", "south korea"], unicodeHex: "U+1F1F0-1F1F7"),
            EmojiItem(emoji: "🇨🇳", name: "Flag: China", shortcode: ":cn:", category: .flags, keywords: ["china"], unicodeHex: "U+1F1E8-1F1F3")
        ]
    }
}
