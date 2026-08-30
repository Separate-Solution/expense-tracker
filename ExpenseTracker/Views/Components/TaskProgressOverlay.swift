import SwiftUI

/// The determinate loader shown over the Data screen while an import, restore
/// or erase runs.
///
/// These tasks hold the main actor — SwiftData's context can't leave it — so
/// they yield between chunks to let this redraw. Without that the screen would
/// freeze on 0% and jump straight to done, which is what an indeterminate
/// spinner did here before.
struct TaskProgressOverlay: View {

    let progress: TaskProgress

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: progress.fraction)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        // Start the sweep at the top rather than at 3 o'clock.
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: progress.fraction)

                    Text("\(progress.percent)%")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(width: 92, height: 92)

                Text(progress.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .shadow(radius: 12, y: 4)
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.label)
        .accessibilityValue("\(progress.percent) percent")
    }
}
