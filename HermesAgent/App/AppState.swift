import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Phase { case loading, unpaired, paired }

    var phase: Phase = .loading
    var displayName: String = "Hermes"
    var relayURL: String = ""
    /// Bumped to request HomeView to pop to root and open Chat (e.g. after resuming a session).
    var openChatRequest: Int = 0

    func openChat() {
        openChatRequest &+= 1
    }

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

    private var _hapticsEnabled: Bool = UserDefaults.standard.object(forKey: "hermes.haptics") as? Bool ?? true
    var hapticsEnabled: Bool {
        get { _hapticsEnabled }
        set {
            _hapticsEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "hermes.haptics")
            Haptics.isEnabled = newValue
        }
    }

    enum ChatTextSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var displayName: String {
            switch self { case .small: return "Small"; case .medium: return "Medium"; case .large: return "Large" }
        }
        var pointSize: CGFloat {
            switch self { case .small: return 14; case .medium: return 16; case .large: return 18 }
        }
    }

    private var _chatTextSize: ChatTextSize = ChatTextSize(rawValue: UserDefaults.standard.string(forKey: "hermes.textsize") ?? "medium") ?? .medium
    var chatTextSize: ChatTextSize {
        get { _chatTextSize }
        set { _chatTextSize = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: "hermes.textsize") }
    }

    private var _showTimestamps: Bool = UserDefaults.standard.object(forKey: "hermes.timestamps") as? Bool ?? true
    var showTimestamps: Bool {
        get { _showTimestamps }
        set { _showTimestamps = newValue; UserDefaults.standard.set(newValue, forKey: "hermes.timestamps") }
    }

    private var _autoExpandThinking: Bool = UserDefaults.standard.object(forKey: "hermes.autothink") as? Bool ?? true
    var autoExpandThinking: Bool {
        get { _autoExpandThinking }
        set { _autoExpandThinking = newValue; UserDefaults.standard.set(newValue, forKey: "hermes.autothink") }
    }

    private var _confirmNewChat: Bool = UserDefaults.standard.object(forKey: "hermes.confirmclear") as? Bool ?? true
    var confirmNewChat: Bool {
        get { _confirmNewChat }
        set { _confirmNewChat = newValue; UserDefaults.standard.set(newValue, forKey: "hermes.confirmclear") }
    }

    private(set) var client: RelayClient
    private(set) var api: RelayAPI
    private(set) var agent: AgentAPI
    /// Owned here (not by ChatView) so an in-flight stream survives leaving the chat screen.
    private(set) var chatViewModel: ChatViewModel!

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
        self.chatViewModel = ChatViewModel(api: api)
        Haptics.isEnabled = _hapticsEnabled
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
