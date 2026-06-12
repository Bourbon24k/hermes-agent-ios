import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Phase { case loading, unpaired, paired }

    var phase: Phase = .loading
    var displayName: String = "Hermes"
    var relayURL: String = ""

    private var _selectedModel: String = UserDefaults.standard.string(forKey: "hermes.model") ?? "claude-sonnet-4-6"
    var selectedModel: String {
        get { _selectedModel }
        set { _selectedModel = newValue; UserDefaults.standard.set(newValue, forKey: "hermes.model") }
    }

    private var _thinkingBudget: ThinkingBudget = ThinkingBudget(rawValue: UserDefaults.standard.string(forKey: "hermes.thinking") ?? "high") ?? .high
    var thinkingBudget: ThinkingBudget {
        get { _thinkingBudget }
        set { _thinkingBudget = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: "hermes.thinking") }
    }

    private(set) var client: RelayClient
    private(set) var api: RelayAPI
    private(set) var agent: AgentAPI

    init() {
        // Keychain survives app deletion but UserDefaults does not. On a fresh install
        // wipe any leftover session so deleting the app truly resets pairing.
        if !UserDefaults.standard.bool(forKey: "hermes.installed") {
            RelaySessionStore.clear()
            UserDefaults.standard.set(true, forKey: "hermes.installed")
        }
        var stored = RelaySessionStore.load()
        #if DEBUG
        if let debugSession = DebugLogin.sessionFromLaunchArguments() {
            stored = debugSession
            print("[DebugLogin] Injected session → relay=\(debugSession.relayBaseURL)")
        }
        #endif
        let client = RelayClient(session: stored)
        self.client = client
        self.api = RelayAPI(client: client)
        self.agent = AgentAPI(client: client)
        phase = stored == nil ? .unpaired : .paired
        displayName = stored?.displayName ?? "Hermes"
        relayURL = stored?.relayBaseURL ?? ""
        Task {
            await client.setOnSessionUpdate { [weak self] session in
                Task { @MainActor in
                    guard let self else { return }
                    if session == nil, self.phase == .paired { self.phase = .unpaired }
                }
            }
        }
    }

    func completePairing(relayBaseURL: String, redeem: RedeemResponse) async {
        let session = RelaySession(
            relayBaseURL: redeem.session.backendEndpoint ?? relayBaseURL,
            userId: redeem.user.id,
            displayName: redeem.user.displayName,
            deviceId: redeem.deviceId,
            accessToken: redeem.auth.accessToken,
            refreshToken: redeem.auth.refreshToken,
            accessExpiresAt: redeem.auth.expiresAt,
            installationId: RelaySessionStore.installationId
        )
        await client.updateSession(session)
        displayName = session.displayName
        relayURL = session.relayBaseURL
        phase = .paired
    }

    func unpair() async {
        try? await api.revoke()
        await client.updateSession(nil)
        phase = .unpaired
    }
}
