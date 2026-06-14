import Foundation

public enum LineContext: Hashable, Sendable {
    case reminder(HabitKind), snoozed(HabitKind), done(HabitKind), mood(Mood), hushOver, shareHeadline(Mood)
}

/// Drip's voice: melodramatic, kind, never shaming. Every line ≤ 70 characters.
public enum Lines {
    public static func all(_ c: LineContext) -> [String] {
        switch c {
        case .reminder(.water): [
            "Sip o'clock. The ocean called, it misses you.",
            "I'm evaporating. Slowly. Dramatically. Drink?",
            "Your brain is 75% water and 25% open tabs. Fix one.",
            "Hydrate or diedrate. I don't make the rules.",
            "A glass of water walks into a bar. It's you. Drink it.",
            "Plants get watered more often than you. Think about it.",
            "Hey. Hey you. Yes, you. Water. Now. Please. 🥺",
            "Your kidneys asked me to pass along a message: 💧",
            "Quick, drink before your next 'quick sync'.",
            "I believe in you. I also believe in water.",
            "This is your sign. Literally. It's a water sign.",
            "Be like me. Be mostly water.",
        ]
        case .reminder(.eyes): [
            "Look 20 feet away for 20 seconds. The wall misses you.",
            "Your eyeballs filed a complaint with HR.",
            "Look away! Something far away wants attention too.",
            "Blink. Now look out a window like a movie protagonist.",
            "20-20-20 time. Your screen will survive without you.",
            "Stare into the distance. Contemplate life. 20 seconds.",
        ]
        case .reminder(.posture): [
            "You're melting into that chair. Un-melt.",
            "Shoulders back. You're a CEO in a biopic now.",
            "Your spine called. It wants to be straight again.",
            "Shrimp posture detected. Become a flamingo.",
            "Sit up like you just got complimented.",
            "Screen tilted? No, that's you. Straighten up!",
        ]
        case .reminder(.stretch): [
            "Stretch break! Reach for the sky, or the snacks.",
            "Your muscles are loading… please stretch to continue.",
            "Wiggle time. Nobody's watching. (I am.)",
            "Arms up! Pretend your code finally compiled.",
            "Stretch like a cat who just woke from a nap.",
            "30 seconds of stretching. Your back will write you a poem.",
        ]
        case .reminder(.breathe): [
            "Breathe with Puff. In for 4… out for 6. Three times.",
            "Your shoulders are up by your ears. Breathe them down.",
            "One slow breath. The inbox will wait.",
            "Puff says: in through the nose, out like a sigh.",
            "Three deep breaths. Cheaper than a spa.",
        ]
        case .reminder(.stand): [
            "Pop! Up you get. You've been sitting a while.",
            "Stand up for a minute. Your chair needs a breather.",
            "Legs check! Stand, stretch, sit if you must.",
            "Pop says stand. Pop is very small but very loud.",
            "Up! Take the next call standing like a CEO.",
        ]
        case .reminder(.walk): [
            "Go for a walk. I'll guard your tabs.",
            "Your legs are still attached. Go check on them.",
            "Walk to the water cooler. Gossip optional.",
            "Stand up! The chair needs a break from you too.",
            "Steps are the new standups. Go take some.",
            "Follow the footprints. They know the way.",
        ]
        case .snoozed(.water): [
            "Fine. I'll just… shrivel here. Quietly. 🥀",
            "5 more minutes. I'm counting every single one.",
            "Snoozed. I've written my will. You get nothing.",
            "Okay. But I'm telling the cactus about this.",
            "Snoozing hydration? Bold. Very bold.",
        ]
        case let .snoozed(kind): [
            "Okay, 5 minutes. I'll be right here. Waiting. 👀",
            "Snoozed. Future you is going to love this.",
            "Fine. But I'm coming back with reinforcements.",
            "I'll allow it. This time. (\(kind.title) is patient.)",
            "5 minutes. Set a timer? I did. I'm the timer.",
        ]
        case .done(.water): [
            "AHHH that's the stuff. I'm plump again! 💧",
            "Hydration achieved. You're basically a fountain.",
            "Refilled! My will has been torn up. I LIVE.",
            "Chef's kiss. Your cells are doing a little dance.",
            "Water level: majestic. Keep it up!",
            "You drank water. Put it on your LinkedIn.",
        ]
        case .done(.eyes): [
            "Eyes refreshed. You can see clearly now. 🎶",
            "Fog cleared. Welcome back, eagle eyes.",
            "20 seconds well spent. Your eyes say thanks.",
            "Distance: gazed. Eyeballs: grateful.",
            "Vision restored. Back to squinting at spreadsheets.",
        ]
        case .done(.posture): [
            "Straight as an arrow. Very regal.",
            "Posture: fixed. Confidence: +10.",
            "Look at you, sitting like a main character.",
            "Spine aligned. Chiropractor weeps with joy.",
            "Now that's the posture of someone who ships.",
        ]
        case .done(.stretch): [
            "Stretched! You're 3% more flexible and 100% cooler.",
            "Muscles: un-crunched. Nice.",
            "That was a stretch. Literally. Well done.",
            "Your joints just sent a thank-you card.",
            "Limber legend. Back to it!",
        ]
        case .done(.breathe): [
            "Ahh. Puff is very proud of that exhale.",
            "Calm unlocked. Carry on, zen master.",
            "Breathing: done. You're basically a monk now.",
            "Lungs refreshed. Stress down one notch.",
            "Puff gives that breath a 10/10.",
        ]
        case .done(.stand): [
            "Standing ovation! (For you, from you.)",
            "Up and at 'em. Pop approves.",
            "Blood flow restored. Legs say thanks.",
            "That was a stand-up job. Literally.",
            "You stood! Sitting is now allowed again.",
        ]
        case .done(.walk): [
            "Welcome back, explorer! Steps: acquired.",
            "Walked! Your chair missed you (it didn't).",
            "Legs: confirmed working. Great success.",
            "You went outside the tab. Proud of you.",
            "Walk complete. Brain rebooted. ✨",
        ]
        case .mood(.hydrated): [
            "We're thriving. Look at us. Glowing.",
            "Fully hydrated. I could be a waterfall.",
            "Plump, happy, and slightly smug.",
            "Life is good. Water is good. You are good.",
            "I'm so hydrated I'm basically a lake.",
            "Vibes: pristine alpine spring.",
            "Hydration level: main character.",
            "10/10 would be a water drop again.",
            "Look at my bounce. Look at it.",
            "I am the drop. The drop is me. Balance.",
        ]
        case .mood(.thirsty): [
            "Hey... not to be dramatic, but... sip?",
            "Getting a little crispy around the edges.",
            "I've been better. I've also been wetter.",
            "Is it hot in here or am I evaporating?",
            "Mildly parched. Moderately concerned.",
            "A sip would really turn my day around.",
            "My inner ocean is more of a puddle now.",
            "Just thinking about water. Normal stuff.",
            "I'm fine. Totally fine. (I'm thirsty.)",
            "Glass half empty energy today.",
        ]
        case .mood(.parched): [
            "I'm a raisin now. Are you happy?",
            "Tell my mom I loved her. 🥀",
            "I see a light... is it a water cooler?",
            "Dehydration arc unlocked. Not a fun arc.",
            "Please. I'm begging. One sip. For me.",
            "I've evaporated so much I'm basically a cloud.",
            "My last words: drink... water...",
            "Sahara called. Asked if I'm okay. I'm not.",
            "Crispy. Wrinkly. Betrayed.",
            "If I had a spine I'd need posture help too.",
        ]
        case .hushOver: [
            "You survived the meeting. Now DRINK.",
            "Meeting over? Hydration time, champ.",
            "That call was long. I kept a list for you.",
            "Mic's off. Bottle's up. Let's go.",
            "Great meeting! Now let's have a great sip.",
        ]
        case .shareHeadline(.hydrated): [
            "Hydration royalty. Bow down.",
            "Drip survived the day. Thriving, even.",
            "Certified human fountain.",
            "Today's forecast: 100% chance of hydration.",
            "The kidneys have issued a formal thank-you.",
        ]
        case .shareHeadline(.thirsty): [
            "A respectable effort. Mildly crispy.",
            "Drip is okay. Drip has seen things.",
            "Could be worse. Could be a raisin.",
            "Half full? Half empty? Half hydrated.",
            "Survived on vibes and occasional sips.",
        ]
        case .shareHeadline(.parched): [
            "Drip nearly evaporated. Pray for Drip.",
            "Today I was a raisin. Tomorrow, a grape.",
            "Hydration: optional, apparently.",
            "The desert called. It wants its human back.",
            "RIP Drip (temporarily).",
        ]
        }
    }

    public static func pick(_ c: LineContext, avoiding: String?, using rng: inout some RandomNumberGenerator) -> String {
        let options = all(c).filter { $0 != avoiding }
        return options.randomElement(using: &rng) ?? all(c)[0]
    }

    public static func pick(_ c: LineContext, avoiding: String? = nil) -> String {
        var rng = SystemRandomNumberGenerator()
        return pick(c, avoiding: avoiding, using: &rng)
    }
}

public extension HabitKind {
    var title: String {
        switch self {
        case .water: "Sip water"
        case .eyes: "Eyes off screen"
        case .posture: "Posture"
        case .stretch: "Stretch"
        case .walk: "Take a walk"
        case .breathe: "Deep breath"
        case .stand: "Stand up"
        }
    }

    /// Short habit noun: "Drip · water".
    var noun: String {
        switch self {
        case .water: "water"
        case .eyes: "eyes"
        case .posture: "posture"
        case .stretch: "stretch"
        case .walk: "walk"
        case .breathe: "breathe"
        case .stand: "stand up"
        }
    }

    var emoji: String {
        switch self {
        case .water: "💧"
        case .eyes: "👀"
        case .posture: "🪑"
        case .stretch: "🙆"
        case .walk: "👣"
        case .breathe: "🌬️"
        case .stand: "🧍"
        }
    }

    var doneLabel: String {
        switch self {
        case .water: "I drank 💧"
        case .eyes: "Looked away 👀"
        case .posture: "Sat up straight"
        case .stretch: "Stretched 🙆"
        case .walk: "Back from walk 👣"
        case .breathe: "Breathed 🌬️"
        case .stand: "Standing 🧍"
        }
    }

    var pitch: String {
        switch self {
        case .water: "Menu bar turns into waves. Ignore it and your screen floods."
        case .eyes: "Your screen fogs up. A tiny wiper clears it after 20 seconds."
        case .posture: "Your whole screen tilts until you sit up straight."
        case .stretch: "The screen wobbles like jelly. Stretch with Drip for 30s."
        case .walk: "Little footprints walk off your screen. Follow them."
        case .breathe: "Puff guides three slow breaths: in for 4, out for 6."
        case .stand: "Pop pops up when you've been sitting too long."
        }
    }
}
