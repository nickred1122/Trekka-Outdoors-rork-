import Foundation
import CoreLocation

nonisolated enum GPXError: LocalizedError {
    case unreadable
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case .unreadable: "That file could not be read as GPX."
        case .noTrackPoints: "No track points were found in that GPX file."
        }
    }
}

/// Parses and writes GPX 1.1 track files.
nonisolated enum GPXCodec {
    static func parse(data: Data, fallbackName: String) throws -> PlannedRoute {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.unreadable }
        guard !delegate.trackPoints.isEmpty else { throw GPXError.noTrackPoints }

        var route = PlannedRoute(
            name: delegate.trackName?.isEmpty == false ? (delegate.trackName ?? fallbackName) : fallbackName,
            source: .imported,
            points: delegate.trackPoints
        )
        let cumulative = RouteMath.cumulativeDistances(of: route.points)
        route.waypoints = delegate.waypoints.enumerated().map { index, entry in
            let nearest = nearestIndex(to: entry.point, in: route.points)
            return Waypoint(
                name: entry.name.isEmpty ? "Waypoint \(index + 1)" : entry.name,
                note: entry.note,
                point: entry.point,
                distanceAlongRoute: cumulative.indices.contains(nearest) ? cumulative[nearest] : 0
            )
        }
        return route
    }

    static func export(_ route: PlannedRoute) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Trekka Outdoors" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(route.name))</name></metadata>

        """
        for waypoint in route.waypoints {
            xml += """
              <wpt lat="\(waypoint.point.latitude)" lon="\(waypoint.point.longitude)">
                <ele>\(waypoint.point.elevation)</ele>
                <name>\(escape(waypoint.name))</name>
                <desc>\(escape(waypoint.note))</desc>
              </wpt>

            """
        }
        xml += "  <trk><name>\(escape(route.name))</name><trkseg>\n"
        for point in route.points {
            xml += "    <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><ele>\(point.elevation)</ele></trkpt>\n"
        }
        xml += "  </trkseg></trk>\n</gpx>\n"
        return xml
    }

    private static func nearestIndex(to point: RoutePoint, in points: [RoutePoint]) -> Int {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (index, candidate) in points.enumerated() {
            let distance = location.distance(from: CLLocation(latitude: candidate.latitude, longitude: candidate.longitude))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private nonisolated final class GPXParserDelegate: NSObject, XMLParserDelegate {
    struct ParsedWaypoint {
        var name: String
        var note: String
        var point: RoutePoint
    }

    var trackPoints: [RoutePoint] = []
    var waypoints: [ParsedWaypoint] = []
    var trackName: String?

    private var currentElement = ""
    private var buffer = ""
    private var pendingCoordinate: (lat: Double, lon: Double)?
    private var pendingElevation: Double = 0
    private var pendingName = ""
    private var pendingNote = ""
    private var isInWaypoint = false
    private var isInTrack = false
    private var hasTrackName = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentElement = elementName
        buffer = ""
        switch elementName {
        case "wpt":
            isInWaypoint = true
            pendingName = ""
            pendingNote = ""
            pendingElevation = 0
            pendingCoordinate = coordinate(from: attributeDict)
        case "trkpt", "rtept":
            pendingElevation = 0
            pendingCoordinate = coordinate(from: attributeDict)
        case "trk", "rte":
            isInTrack = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            pendingElevation = Double(text) ?? 0
        case "name":
            if isInWaypoint {
                pendingName = text
            } else if isInTrack, !hasTrackName, !text.isEmpty {
                trackName = text
                hasTrackName = true
            } else if trackName == nil, !text.isEmpty {
                trackName = text
            }
        case "desc", "cmt":
            if isInWaypoint { pendingNote = text }
        case "trkpt", "rtept":
            if let coordinate = pendingCoordinate {
                trackPoints.append(RoutePoint(latitude: coordinate.lat, longitude: coordinate.lon, elevation: pendingElevation))
            }
            pendingCoordinate = nil
        case "wpt":
            if let coordinate = pendingCoordinate {
                waypoints.append(
                    ParsedWaypoint(
                        name: pendingName,
                        note: pendingNote,
                        point: RoutePoint(latitude: coordinate.lat, longitude: coordinate.lon, elevation: pendingElevation)
                    )
                )
            }
            isInWaypoint = false
            pendingCoordinate = nil
        case "trk", "rte":
            isInTrack = false
        default:
            break
        }
        buffer = ""
    }

    private func coordinate(from attributes: [String: String]) -> (lat: Double, lon: Double)? {
        guard let latitude = Double(attributes["lat"] ?? ""), let longitude = Double(attributes["lon"] ?? "") else {
            return nil
        }
        return (latitude, longitude)
    }
}
