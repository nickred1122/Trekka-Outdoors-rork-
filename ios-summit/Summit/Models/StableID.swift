import Foundation

/// Deterministic identifiers for content the app computes rather than stores.
///
/// Default page layouts are built on demand, so minting a fresh `UUID()` on
/// every read would hand each read a different identity — an edit would then
/// never find the page it was meant to change, and would silently do nothing.
/// Seeding from a stable string keeps a default page recognisable across reads,
/// launches and both devices.
nonisolated enum StableID {
    /// A UUID derived purely from `seed`, identical everywhere for the same seed.
    static func uuid(seed: String) -> UUID {
        // FNV-1a for the low half, then a bit-mixer for the high half. Not a
        // cryptographic hash — it only needs to be stable and well spread.
        var low: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            low = (low ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        var high = low ^ 0x9e37_79b9_7f4a_7c15
        high = (high ^ (high >> 30)) &* 0xbf58_476d_1ce4_e5b9
        high = (high ^ (high >> 27)) &* 0x94d0_49bb_1331_11eb
        high ^= high >> 31

        let bytes: [UInt8] = (0..<8).map { UInt8(truncatingIfNeeded: low >> (UInt64($0) * 8)) }
            + (0..<8).map { UInt8(truncatingIfNeeded: high >> (UInt64($0) * 8)) }

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Identity of the page at `index` in a sport's default stack. The watch app
    /// uses the same seed, so a layout edited on either device lines up.
    static func defaultPage(sport: String, index: Int) -> UUID {
        uuid(seed: "screen.\(sport).\(index)")
    }
}
