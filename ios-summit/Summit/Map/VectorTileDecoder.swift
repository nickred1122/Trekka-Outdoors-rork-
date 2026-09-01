import Foundation
import CoreGraphics

/// What a vector tile feature is shaped like.
nonisolated enum VectorGeometryKind: Int, Sendable {
    case point = 1
    case line = 2
    case polygon = 3
}

/// One drawable thing from a vector tile — a lake, a footpath, a wood.
nonisolated struct VectorFeature: Sendable {
    let kind: VectorGeometryKind
    /// Geometry in tile-local space, normalised 0...1 with y running down.
    /// Storing it normalised means a tile decodes once and draws at any zoom.
    let paths: [[CGPoint]]
    /// OpenMapTiles' broad category, e.g. `path`, `river`, `wood`.
    let className: String
    /// The finer distinction, e.g. `footway` versus `track`.
    let subclass: String
    let name: String
    /// `bridge` or `tunnel` where the way leaves the ground.
    let brunnel: String
}

nonisolated struct VectorTile: Sendable {
    /// Features by source-layer name.
    let layers: [String: [VectorFeature]]

    static let empty = VectorTile(layers: [:])

    var isEmpty: Bool { layers.isEmpty }
}

/// A hand-written reader for Mapbox Vector Tiles.
///
/// Vector tiles are protobuf, and pulling in a whole protobuf runtime for one
/// small schema would be a poor trade — the format is four messages deep and
/// stable, so it is decoded directly here.
///
/// Only the attribute keys and source layers the cartography actually draws are
/// kept. A planet tile carries the name of every feature in dozens of
/// languages; decoding all of that would cost far more memory than the map
/// needs.
nonisolated enum VectorTileDecoder {
    /// The only attributes the style branches on.
    private static let wantedKeys: Set<String> = ["class", "subclass", "name", "brunnel"]

    /// Decodes a tile, skipping any layer the style does not draw.
    static func decode(_ data: Data, layers wanted: Set<String>) -> VectorTile {
        guard !data.isEmpty else { return .empty }
        let bytes = [UInt8](data)
        var reader = ProtoReader(bytes: bytes, from: 0, to: bytes.count)
        var layers: [String: [VectorFeature]] = [:]

        while let tag = reader.readTag() {
            // Field 3 of a Tile is a Layer. Anything else is not ours.
            guard tag.field == 3, tag.wire == 2 else {
                reader.skip(tag.wire)
                continue
            }
            guard let layerReader = reader.subReader() else { break }

            // Probe the name on a copy first: readers are values sharing one
            // byte array, so this costs nothing and saves decoding the string
            // tables of layers we are going to throw away.
            var probe = layerReader
            guard let name = probe.probeLayerName(), wanted.contains(name) else { continue }

            var body = layerReader
            let features = decodeLayer(&body)
            if !features.isEmpty {
                layers[name, default: []].append(contentsOf: features)
            }
        }

        return VectorTile(layers: layers)
    }

    // MARK: - Layer

    private static func decodeLayer(_ reader: inout ProtoReader) -> [VectorFeature] {
        var extent: Double = 4096
        var keys: [String] = []
        var values: [String] = []
        var featureReaders: [ProtoReader] = []

        while let tag = reader.readTag() {
            switch (tag.field, tag.wire) {
            case (2, 2):
                if let sub = reader.subReader() { featureReaders.append(sub) }
            case (3, 2):
                keys.append(reader.readString() ?? "")
            case (4, 2):
                if var sub = reader.subReader() { values.append(decodeValue(&sub)) }
            case (5, 0):
                if let raw = reader.readVarint(), raw > 0 { extent = Double(raw) }
            default:
                reader.skip(tag.wire)
            }
        }

        // Only the keys the style reads are worth looking up per feature.
        var keptKeys: [Int: String] = [:]
        for (index, key) in keys.enumerated() where wantedKeys.contains(key) {
            keptKeys[index] = key
        }

        var features: [VectorFeature] = []
        features.reserveCapacity(featureReaders.count)
        for var featureReader in featureReaders {
            if let feature = decodeFeature(&featureReader, keys: keptKeys, values: values, extent: extent) {
                features.append(feature)
            }
        }
        return features
    }

    /// A Value is a one-of; whichever field is present becomes a string, since
    /// that is all the style compares against.
    private static func decodeValue(_ reader: inout ProtoReader) -> String {
        while let tag = reader.readTag() {
            switch (tag.field, tag.wire) {
            case (1, 2):
                return reader.readString() ?? ""
            case (2, 5):
                let raw = reader.readFixed32() ?? 0
                return String(Float(bitPattern: raw))
            case (3, 1):
                let raw = reader.readFixed64() ?? 0
                return String(Double(bitPattern: raw))
            case (4, 0), (5, 0):
                return String(reader.readVarint() ?? 0)
            case (6, 0):
                let raw = reader.readVarint() ?? 0
                return String(ProtoReader.zigzag64(raw))
            case (7, 0):
                return (reader.readVarint() ?? 0) == 0 ? "false" : "true"
            default:
                reader.skip(tag.wire)
            }
        }
        return ""
    }

    // MARK: - Feature

    private static func decodeFeature(
        _ reader: inout ProtoReader,
        keys: [Int: String],
        values: [String],
        extent: Double
    ) -> VectorFeature? {
        var kindRaw: Int = 0
        var tagPairs: [UInt32] = []
        var geometry: [UInt32] = []

        while let tag = reader.readTag() {
            switch (tag.field, tag.wire) {
            case (2, 2):
                tagPairs = reader.readPackedVarints()
            case (3, 0):
                kindRaw = Int(reader.readVarint() ?? 0)
            case (4, 2):
                geometry = reader.readPackedVarints()
            default:
                reader.skip(tag.wire)
            }
        }

        guard let kind = VectorGeometryKind(rawValue: kindRaw), !geometry.isEmpty else { return nil }

        var className = ""
        var subclass = ""
        var name = ""
        var brunnel = ""

        var pairIndex = 0
        while pairIndex + 1 < tagPairs.count {
            let keyIndex = Int(tagPairs[pairIndex])
            let valueIndex = Int(tagPairs[pairIndex + 1])
            pairIndex += 2
            guard let key = keys[keyIndex], valueIndex < values.count else { continue }
            let value = values[valueIndex]
            switch key {
            case "class": className = value
            case "subclass": subclass = value
            case "name": name = value
            case "brunnel": brunnel = value
            default: break
            }
        }

        let paths = decodeGeometry(geometry, extent: extent, kind: kind)
        guard !paths.isEmpty else { return nil }

        return VectorFeature(
            kind: kind,
            paths: paths,
            className: className,
            subclass: subclass,
            name: name,
            brunnel: brunnel
        )
    }

    // MARK: - Geometry

    /// Walks the command/parameter stream into normalised paths.
    ///
    /// Commands are `(id | count << 3)` followed by that many zig-zag encoded
    /// coordinate deltas, so position is cumulative across the whole feature.
    private static func decodeGeometry(
        _ geometry: [UInt32],
        extent: Double,
        kind: VectorGeometryKind
    ) -> [[CGPoint]] {
        let minimumPoints: Int = kind == .point ? 1 : 2
        let inverseExtent: Double = 1 / extent

        var paths: [[CGPoint]] = []
        var current: [CGPoint] = []
        var x: Int32 = 0
        var y: Int32 = 0
        var index = 0

        while index < geometry.count {
            let command = geometry[index]
            index += 1
            let commandID: UInt32 = command & 0x7
            let count = Int(command >> 3)

            if commandID == 7 {
                // ClosePath: repeat the first point so a stroked outline meets.
                if current.count > 1, let first = current.first {
                    current.append(first)
                }
                continue
            }

            guard commandID == 1 || commandID == 2, count > 0 else { break }

            for _ in 0..<count {
                guard index + 1 < geometry.count else { break }
                let deltaX = ProtoReader.zigzag32(geometry[index])
                let deltaY = ProtoReader.zigzag32(geometry[index + 1])
                index += 2
                x = x &+ deltaX
                y = y &+ deltaY
                let point = CGPoint(x: Double(x) * inverseExtent, y: Double(y) * inverseExtent)

                if commandID == 1 {
                    // MoveTo begins a new ring, line or point.
                    if current.count >= minimumPoints { paths.append(current) }
                    current = [point]
                } else {
                    current.append(point)
                }
            }
        }

        if current.count >= minimumPoints { paths.append(current) }
        return paths
    }
}

// MARK: - Protobuf reading

/// A cursor over protobuf bytes.
///
/// A value type sharing one `[UInt8]`, so taking a sub-reader for a nested
/// message is a retain rather than a copy.
///
/// Explicitly `nonisolated`: this project defaults every type to the main actor,
/// and tile decoding runs on a background task. Without this the reader would be
/// main-actor bound and the decoder could not touch it off the main thread.
private nonisolated struct ProtoReader {
    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    init(bytes: [UInt8], from: Int, to: Int) {
        self.bytes = bytes
        self.index = max(0, from)
        self.end = min(to, bytes.count)
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < end {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    mutating func readTag() -> (field: Int, wire: Int)? {
        guard let raw = readVarint(), raw > 0 else { return nil }
        return (Int(raw >> 3), Int(raw & 0x7))
    }

    mutating func readFixed32() -> UInt32? {
        guard index + 4 <= end else { index = end; return nil }
        var value: UInt32 = 0
        for offset in 0..<4 {
            value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset))
        }
        index += 4
        return value
    }

    mutating func readFixed64() -> UInt64? {
        guard index + 8 <= end else { index = end; return nil }
        var value: UInt64 = 0
        for offset in 0..<8 {
            value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
        }
        index += 8
        return value
    }

    mutating func subReader() -> ProtoReader? {
        guard let length = readVarint() else { return nil }
        let from = index
        let to = index + Int(length)
        guard to <= end else { index = end; return nil }
        index = to
        return ProtoReader(bytes: bytes, from: from, to: to)
    }

    mutating func readString() -> String? {
        guard let length = readVarint() else { return nil }
        let from = index
        let to = index + Int(length)
        guard to <= end else { index = end; return nil }
        index = to
        return String(decoding: bytes[from..<to], as: UTF8.self)
    }

    mutating func readPackedVarints() -> [UInt32] {
        guard var sub = subReader() else { return [] }
        var values: [UInt32] = []
        values.reserveCapacity(32)
        while let value = sub.readVarint() {
            values.append(UInt32(truncatingIfNeeded: value))
        }
        return values
    }

    /// Reads only far enough to learn a layer's name, then stops.
    mutating func probeLayerName() -> String? {
        while let tag = readTag() {
            if tag.field == 1, tag.wire == 2 { return readString() }
            skip(tag.wire)
        }
        return nil
    }

    mutating func skip(_ wire: Int) {
        switch wire {
        case 0:
            _ = readVarint()
        case 1:
            index = min(end, index + 8)
        case 2:
            if let length = readVarint() { index = min(end, index + Int(length)) }
        case 5:
            index = min(end, index + 4)
        default:
            index = end
        }
    }

    static func zigzag32(_ value: UInt32) -> Int32 {
        Int32(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
    }

    static func zigzag64(_ value: UInt64) -> Int64 {
        Int64(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
    }
}
