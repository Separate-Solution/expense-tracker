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
    ///
    /// A rejected write is also undone. The context holds the edit in memory
    /// whether or not it reached disk, so leaving it would show a deleted row
    /// as gone and an archived account as archived while the store disagrees —
    /// until the next launch put it back. Rolling back means the screen and the
    /// store always say the same thing, and callers don't each have to
    /// hand-write the inverse of whatever they just did.
    /// - Returns: nil when the save went through, or the error to show.
    func saveReportingFailure() -> Error? {
        guard hasChanges else { return nil }
        do {
            try save()
            return nil
        } catch {
            rollback()
            return error
        }
    }
}

extension View {

    /// Shows why a write failed, for screens that would otherwise carry on as
    /// though it hadn't.
    /// - Parameter failure: The error to show; cleared when dismissed.
    /// - Returns: The view with the alert attached.
    func saveFailureAlert(_ failure: Binding<Error?>) -> some View {
        alert("Couldn't save", isPresented: Binding(
            get: { failure.wrappedValue != nil },
            set: { if !$0 { failure.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { failure.wrappedValue = nil }
        } message: {
            Text(failure.wrappedValue?.localizedDescription ?? "")
        }
    }
}
