import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A file staged in the temporary directory, ready for the share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
}

enum ExportFileWriter {

    static func write(_ data: Data, named name: String) throws -> ExportedFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        // Overwrite any file left behind by a previous export on the same day.
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return ExportedFile(url: url)
    }

    static func write(_ text: String, named name: String) throws -> ExportedFile {
        try write(Data(text.utf8), named: name)
    }

    static func timestampedName(prefix: String, extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(prefix)-\(formatter.string(from: Date())).\(ext)"
    }
}

extension UTType {
    /// Backups are plain JSON; declaring it explicitly keeps the importer picky.
    static var expenseBackup: UTType { .json }
}
