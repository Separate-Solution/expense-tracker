import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A file staged in the temporary directory, ready for the share sheet.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL

    /// The file name shown in the share sheet.
    var name: String { url.lastPathComponent }
}

enum ExportFileWriter {

    /// Stages `data` as a file in the temporary Exports directory.
    /// An existing file with the same name is replaced.
    /// - Parameters:
    ///   - data: The file contents.
    ///   - name: File name including its extension.
    /// - Returns: The staged file, ready to hand to the share sheet.
    /// - Throws: Any `FileManager` error from creating or writing the file.
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

    /// Stages `text` as a UTF-8 file. See `write(_:named:)` for details.
    static func write(_ text: String, named name: String) throws -> ExportedFile {
        try write(Data(text.utf8), named: name)
    }

    /// Builds a file name like `expenses-2026-08-29-0948.csv`.
    /// The timestamp is POSIX-formatted so it sorts and never localises.
    /// - Parameters:
    ///   - prefix: Leading part of the name.
    ///   - ext: File extension, without the dot.
    /// - Returns: The composed file name.
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
