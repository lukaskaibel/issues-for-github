#if os(macOS)
import AppKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model

    @State private var deviceCode: DeviceFlow.Code?
    @State private var working = false
    @State private var errorText: String?
    @State private var showTokenField = false
    @State private var token = ""

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text(.signInHeadlineMac)
                    .font(.system(size: 22, weight: .semibold))
                Text(.signInSubheadline)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            if let deviceCode {
                codeCard(deviceCode)
            } else {
                VStack(spacing: 10) {
                    if DeviceFlow.configuredClientID != nil {
                        Button(.signInWithGitHub) { startDeviceFlow() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    if GitHubCLI.isAvailable {
                        Button(.useGitHubCLILogin) { useCLI() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(showTokenField ? .hideTokenField : .usePersonalAccessTokenMac) {
                        showTokenField.toggle()
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if showTokenField {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                SecureField(.tokenFieldPlaceholder, text: $token)
                                    .textFieldStyle(.plain)
                                    .focusOnAppear()
                                    .padding(.horizontal, 10)
                                    .frame(width: 320, height: 28)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.control))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.chipBorder, lineWidth: 1))
                                    .onSubmit(useToken)
                                Button(.signInMac, action: useToken)
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                            Text(.tokenStoredInKeychain)
                                .font(.small)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }

                    Button(.exploreWithSampleData) { model.enterDemo() }
                        .buttonStyle(PlainPressStyle())
                        .font(.uiMedium)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 6)
                        .help(Text(.sampleDataTooltip))
                }
                .disabled(working)
            }

            if let errorText {
                Text(errorText)
                    .font(.small)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Theme.overlay, value: showTokenField)
        .animation(Theme.overlay, value: deviceCode?.userCode)
    }

    private func codeCard(_ code: DeviceFlow.Code) -> some View {
        VStack(spacing: 12) {
            Text(.enterCodeOnGitHub)
                .foregroundStyle(Theme.textSecondary)
            Text(code.userCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .tracking(2)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button(.copyCodeAndOpenGitHubMac) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.verificationURL)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(.cancel) { deviceCode = nil }
                    .buttonStyle(SecondaryButtonStyle())
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(.waitingForApproval).font(.small).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelBorder, lineWidth: 1))
    }

    private func startDeviceFlow() {
        guard let clientID = DeviceFlow.configuredClientID else { return }
        errorText = nil
        working = true
        Task {
            defer { working = false }
            do {
                let flow = DeviceFlow(clientID: clientID)
                let code = try await flow.start()
                deviceCode = code
                let token = try await flow.waitForToken(code)
                guard deviceCode?.deviceCode == code.deviceCode else { return }
                await model.auth.signIn(token: token)
                deviceCode = nil
                model.completeSignIn()
            } catch {
                deviceCode = nil
                errorText = error.localizedDescription
            }
        }
    }

    private func useCLI() {
        errorText = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await model.auth.signInWithGitHubCLI()
                model.completeSignIn()
            } catch {
                errorText = String(localized: .gitHubCLINotSignedIn)
            }
        }
    }

    private func useToken() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        errorText = nil
        Task {
            await model.auth.signIn(token: value)
            token = ""
            model.completeSignIn()
        }
    }
}
#endif
