import Foundation

/// The word shown while a session works, in the spirit of Claude Code's own
/// spinner ("Pondering…"). Hooks don't carry Claude Code's actual word, so we
/// pick our own: one per turn, chosen from a seed so it doesn't flicker and
/// the store stays deterministic.
public enum WorkingVerb {
    public static let all = [
        "Pondering", "Noodling", "Tinkering", "Percolating", "Mulling", "Brewing",
        "Scheming", "Puzzling", "Conjuring", "Simmering", "Musing", "Crafting",
        "Wrangling", "Cogitating", "Ruminating", "Doodling", "Fiddling", "Whirring",
        "Concocting", "Untangling",
    ]

    /// A verb for `seed` (e.g. session id + turn start). Same seed, same verb.
    public static func pick(seed: String) -> String {
        // FNV-1a: stable across launches, unlike Hasher.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return all[Int(hash % UInt64(all.count))]
    }

    static func activity(sessionID: String, turnStart: Date) -> String {
        pick(seed: "\(sessionID)|\(turnStart.timeIntervalSince1970)") + "…"
    }
}
