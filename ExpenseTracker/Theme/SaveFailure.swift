import SwiftUI
import SwiftData

extension ModelContext {

    /// Saves, describing the failure instead of discarding it.
    ///
    /// `try? save()` is the wrong shape wherever the screen goes on to tell the
    /// user the write worked — closing a sheet, firing the success haptic, or
    /// simply leaving the change on screen. The context keeps unsaved edits in
    /// memory, so a `@Query` still shows them and everything looks right until
    /// the app is next launched and they are gone.
    /// - Returns: nil when the save went through, or a message to show.
    func saveReportingFailure() -> String? {
        guard hasChanges else { return nil }
        do {
            try save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

extension View {

    /// Shows why a write failed, for screens that would otherwise carry on as
    /// though it hadn't.
    /// - Parameter message: The failure to show; cleared when dismissed.
    /// - Returns: The view with the alert attached.
    func saveFailureAlert(_ message: Binding<String?>) -> some View {
        alert("Couldn't save", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
