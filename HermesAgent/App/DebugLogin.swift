import Foundation

// MARK: - Debug login bypass
//
// Usage (Xcode scheme → Run → Arguments):
//   -HERMES_DEBUG_TOKEN  <accessToken>
//   -HERMES_DEBUG_REFRESH <refreshToken>
//   -HERMES_DEBUG_RELAY   https://193.23.201.2.sslip.io/v1  (optional, defaults to this)
//   -HERMES_DEBUG_OPEN    profiles | settings | skills       (optional, auto-navigate)
//
// Or simply set HERMES_DEBUG_TOKEN to get paired; other values have sensible defaults.

#if DEBUG
enum DebugLogin {

    /// Returns a pre-built `RelaySession` from launch arguments, or `nil` if not set.
    static func sessionFromLaunchArguments() -> RelaySession? {
        let defaults = UserDefaults.standard

        guard let accessToken = defaults.string(forKey: "HERMES_DEBUG_TOKEN"),
              !accessToken.isEmpty
        else { return nil }

        let refreshToken = defaults.string(forKey: "HERMES_DEBUG_REFRESH") ?? ""
        let relay = defaults.string(forKey: "HERMES_DEBUG_RELAY") ?? "https://193.23.201.2.sslip.io/v1"

        return RelaySession(
            relayBaseURL: relay,
            userId: "debug-user",
            displayName: "Debug",
            deviceId: "debug-device",
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: Date.distantFuture,
            installationId: "99999999-9999-9999-9999-999999999999"
        )
    }

    /// The destination to open on launch, read from `-HERMES_DEBUG_OPEN`.
    static var debugOpenDestination: String? {
        UserDefaults.standard.string(forKey: "HERMES_DEBUG_OPEN")
    }
}
#endif
