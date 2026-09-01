import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// Wraps GPX text so routes can be exported through the system file exporter.
nonisolated struct GPXDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.xml] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Tight map region centred on a single coordinate.
nonisolated func MKCoordinateRegionAround(
    _ coordinate: CLLocationCoordinate2D,
    metres: CLLocationDistance = 900
) -> MKCoordinateRegion {
    MKCoordinateRegion(center: coordinate, latitudinalMeters: metres, longitudinalMeters: metres)
}
