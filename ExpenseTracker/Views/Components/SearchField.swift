import SwiftUI

/// Search box that sits above a list rather than in the navigation bar's search
/// drawer. `.searchable` with a pinned drawer collapses the large navigation
/// title on iOS 27, so screens that want both a large title and a search box
/// that is visible on arrival use this instead.
struct SearchField: View {

    @Binding var text: String
    var prompt: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            // The focus tap lives behind the row rather than over it: a gesture on
            // the whole HStack competes with the clear button's own tap.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }
        )
    }
}
