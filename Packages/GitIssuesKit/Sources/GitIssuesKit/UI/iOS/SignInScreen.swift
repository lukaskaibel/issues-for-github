#if os(iOS)
import AuthenticationServices
import SwiftUI
import UIKit

/// Signing in: with GitHub (the device flow, as on the Mac), with a personal access token, with the login
/// shared from the Mac through iCloud Keychain, or without an account on sample data.
struct SignInScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var flow = DeviceSignIn()
    @State private var showToken = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            Theme.panel.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 40)
                VStack(spacing: 22) {
                    AppIconImage(choice: scheme == .dark ? .cardDark : .cardLight, size: 108)
                        .shadow(color: Theme.shadow, radius: 18, y: 10)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text("Your GitHub issues, wherever you are")
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Everything stays in GitHub Projects. Teammates who don't use this app see the same board on github.com.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 420)
                }
                .padding(.horizontal, 32)
                Spacer(minLength: 32)
                if let code = flow.code {
                    codeCard(code)
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                } else {
                    actions
                        .padding(.horizontal, 20)
                }
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                }
                Spacer(minLength: 24).frame(maxHeight: 40)
            }
            .frame(maxWidth: 520)
        }
        .animation(Theme.overlay, value: flow.code?.userCode)
        .sheet(isPresented: $showToken) {
            TokenSignInSheet()
        }
        .onAppear(perform: useSharedLogin)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { useSharedLogin() }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if DeviceFlow.configuredClientID != nil {
                Button {
                    startDeviceFlow()
                } label: {
                    Text("Sign in with GitHub")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .disabled(flow.working)
            }
            if model.auth.sharedLoginAvailable {
                Button {
                    if model.auth.adoptSharedLogin(force: true) { model.completeSignIn() }
                } label: {
                    Label("Use the Login from Your Mac", systemImage: "key.icloud")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glass)
            }
            Button {
                showToken = true
            } label: {
                Label("Use a Personal Access Token", systemImage: "key")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(DeviceFlow.configuredClientID == nil ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
            Button("Explore with Sample Data") {
                model.enterDemo()
            }
            .font(.subheadline.weight(.medium))
            .padding(.top, 4)
            Text("Signed in on your Mac? With iCloud Keychain on, this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone") signs in by itself.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func codeCard(_ code: DeviceFlow.Code) -> some View {
        VStack(spacing: 14) {
            Text("Enter this code on GitHub")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text(code.userCode)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .tracking(3)
                .textSelection(.enabled)
                .accessibilityLabel("Code \(code.userCode.map(String.init).joined(separator: " "))")
            Button {
                flow.openGitHub()
            } label: {
                Text("Copy Code and Open GitHub")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for you to approve…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("Cancel") { flow.cancel() }
                .font(.subheadline)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func startDeviceFlow() {
        errorText = nil
        flow.start { token in
            await model.auth.signIn(token: token)
            model.completeSignIn()
        } failed: { message in
            errorText = message
        }
    }

    /// Signs in by itself when another of the user's devices shared its login.
    private func useSharedLogin() {
        if model.auth.adoptSharedLogin() { model.completeSignIn() }
    }
}

/// Lets two button styles be chosen at run time.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<Style: PrimitiveButtonStyle>(_ style: Style) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// GitHub's device flow on iPhone and iPad: the code is copied, github.com opens in a sheet that shares
/// Safari's login, and the sheet closes by itself once GitHub reports the approval.
@MainActor
@Observable
final class DeviceSignIn {
    private(set) var code: DeviceFlow.Code?
    private(set) var working = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchor()

    func start(signedIn: @escaping @MainActor (String) async -> Void, failed: @escaping @MainActor (String) -> Void) {
        guard let clientID = DeviceFlow.configuredClientID else { return }
        working = true
        task = Task {
            defer {
                working = false
                closeBrowser()
            }
            do {
                let flow = DeviceFlow(clientID: clientID)
                let code = try await flow.start()
                self.code = code
                openGitHub()
                let token = try await flow.waitForToken(code)
                guard self.code?.deviceCode == code.deviceCode else { return }
                self.code = nil
                await signedIn(token)
            } catch is CancellationError {
                code = nil
            } catch {
                code = nil
                failed(error.localizedDescription)
            }
        }
    }

    /// Copies the code and shows GitHub's page for entering it.
    func openGitHub() {
        guard let code else { return }
        UIPasteboard.general.string = code.userCode
        closeBrowser()
        let session = ASWebAuthenticationSession(url: code.verificationURL, callback: .customScheme("gitissues")) { _, _ in }
        session.presentationContextProvider = anchor
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func cancel() {
        task?.cancel()
        task = nil
        code = nil
        closeBrowser()
    }

    private func closeBrowser() {
        session?.cancel()
        session = nil
    }
}

/// Where the GitHub sheet is shown: the app's key window.
private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first { return window }
            // The sign-in screen is on screen while GitHub's page opens, so its window is found above.
            return UIWindow(windowScene: scenes[0])
        }
    }
}

/// Signing in with a personal access token: pasted, checked with GitHub, then saved.
private struct TokenSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var checking = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private static let createURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,project,read:org&description=Issues")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("ghp_…", text: $token)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { token = first.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonBorderShape(.capsule)
                } header: {
                    Text("Personal access token")
                } footer: {
                    Text("A classic token with the repo, project and read:org scopes. It is kept in iCloud Keychain and only sent to api.github.com.")
                }
                Section {
                    Link(destination: Self.createURL) {
                        Label("Create a Token on GitHub", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Opens GitHub with the right scopes already selected.")
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Sign In with a Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if checking {
                        ProgressView()
                    } else {
                        Button("Sign In", action: signIn)
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func signIn() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !checking else { return }
        checking = true
        errorText = nil
        Task {
            defer { checking = false }
            do {
                try await AuthStore.validate(value)
                await model.auth.signIn(token: value)
                dismiss()
                model.completeSignIn()
            } catch APIError.unauthorized {
                errorText = "GitHub didn't accept this token. Check that it's complete and hasn't expired."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
#endif
