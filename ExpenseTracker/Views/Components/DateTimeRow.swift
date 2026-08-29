import SwiftUI

/// Form row for picking a transaction's date *and* time.
///
/// Tapping the row reveals the system wheel picker inline. The wheel rather
/// than the graphical calendar: the calendar sheet only offers a day, and it
/// covers the rest of the form while it is open, which makes checking the
/// other fields against the date awkward.
struct DateTimeRow: View {

    var label: String = "Date"
    @Binding var selection: Date
    /// Optional lower bound, used where a date can't precede another one.
    var range: PartialRangeFrom<Date>?

    @State private var isExpanded = false

    var body: some View {
        Group {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(selection.formatted(Formatters.dateAndTime))
                        .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the picker" : "Shows the date and time picker")

            if isExpanded {
                picker
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let range {
            DatePicker(label, selection: $selection, in: range, displayedComponents: [.date, .hourAndMinute])
        } else {
            DatePicker(label, selection: $selection, displayedComponents: [.date, .hourAndMinute])
        }
    }
}
