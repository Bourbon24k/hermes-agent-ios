import SwiftUI
import UIKit

struct PairingView: View {
    @Environment(AppState.self) private var appState
    @State private var relayURL = ""
    @State private var code = ""
    @State private var showScanner = false
    @State private var isWorking = false
    @State private var errorText: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Spacer(minLength: 40)
                HermesWordmark(size: 44)
                Text("Connect to Hermes Agent on your computer")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 28)

                steps

                VStack(spacing: 12) {
                    field(title: "Relay URL", placeholder: "https://…/v1", text: $relayURL, mono: true)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    field(title: "Pairing code", placeholder: "XXXX-XXXX", text: $code, mono: true)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($codeFocused)
                }
                .padding(.horizontal, 20)

                if isWorking {
                    ProgressView().tint(Theme.accent)
                } else {
                    VStack(spacing: 12) {
                        Button(action: pair) {
                            Text("Pair")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .background(canPair ? Theme.accent : Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(canPair ? .black : Theme.textTertiary)
                        .disabled(!canPair)

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.failure)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showScanner) {
            scannerSheet
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step("1", "On your computer run `hermes-mobile pair-phone`")
            step("2", "Scan the QR code, or type the relay URL + 8-char code below")
        }
        .padding(16)
        .cardStyle()
        .padding(.horizontal, 20)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption.bold()).frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle()).foregroundStyle(.black)
            Text(.init(text)).font(.subheadline).foregroundStyle(Theme.textPrimary)
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.textTertiary)
            TextField(placeholder, text: text)
                .font(mono ? Theme.monoFont(15) : .body)
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var scannerSheet: some View {
        ZStack(alignment: .top) {
            QRScannerView { value in
                showScanner = false
                if let qr = PairingQR.decode(from: value) {
                    relayURL = qr.relay
                    code = qr.code
                    pair()
                } else {
                    errorText = "This QR code is not a Hermes pairing code."
                }
            }
            .ignoresSafeArea()
            Text("Scan the QR from `hermes-mobile pair-phone`")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white).padding(.top, 18)
        }
        .presentationDragIndicator(.visible)
    }

    private var canPair: Bool {
        !normalizedCode.isEmpty && URL(string: normalizedRelay) != nil && normalizedRelay.hasPrefix("http")
    }

    private var normalizedCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private var normalizedRelay: String {
        var url = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        return url
    }

    private func pair() {
        codeFocused = false
        errorText = nil
        isWorking = true
        let relay = normalizedRelay
        let theCode = normalizedCode
        Task {
            defer { isWorking = false }
            do {
                let device = RelayAPI.deviceInfo()
                let redeem = try await RelayAPI.redeem(relayBaseURL: relay, code: theCode, device: device)
                await appState.completePairing(relayBaseURL: relay, redeem: redeem)
            } catch let error as RelayAPIError {
                errorText = error.localizedDescription
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
