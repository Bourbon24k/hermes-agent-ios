import UIKit

/// Centralized haptic feedback. Toggleable from Settings (AppState.hapticsEnabled).
@MainActor
enum Haptics {
    static var isEnabled = true

    /// Light tap — button presses, selections.
    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium impact — message sent.
    static func send() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Selection change — pickers, slash commands.
    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Success notification — reply finished, model switched.
    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error notification.
    static func error() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
