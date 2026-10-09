import SwiftUI

struct AuthView: View {
    enum Mode: Hashable { case signIn, signUp, verify, reset, resetConfirm }
    private enum Field: Hashable { case email(Mode), password(Mode), code(Mode), nickname, givenName, familyName }
    @Environment(APIClient.self) private var api
    @State private var path: [Mode] = []
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var gender = "Other"
    @State private var code = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var resending = false
    @State private var error: String?
    @State private var feedback: (mode: Mode, text: String)?
    @State private var policy: PolicyDocument?
    @State private var policyError: String?
    @State private var loadingPolicy = false
    @State private var legal: PolicySheet?
    @State private var editedEmail = false
    @State private var editedPassword = false
    @State private var resendAfter = Date.distantPast
    @FocusState private var focus: Field?
    private var mode: Mode { path.last ?? .signIn }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            form(.signIn)
                .navigationDestination(for: Mode.self) { form($0) }
        }
        .sheet(item: $legal) { PolicyTextView(sheet: $0) }
        .task { await loadPolicies() }
        .onChange(of: path) { _, _ in
            focus = nil; error = nil; password = ""; code = ""
            editedEmail = false; editedPassword = false; agreed = false
            if feedback?.mode != mode { feedback = nil }
        }
        .onChange(of: focus) { old, _ in
            if case .email(_)? = old { editedEmail = true }
            if case .password(_)? = old { editedPassword = true }
        }
    }

    private func form(_ screen: Mode) -> some View {
        Form {
            if screen == .signIn {
                Section {
                    HStack(alignment: .center, spacing: 12) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PinHaoYun").font(.title.bold())
                            Text("Your photos and videos, together.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear)
            }
            if screen == .verify || screen == .resetConfirm {
                Section {
                    Text("A verification code was sent to")
                    Text(normalizedEmail).font(.headline).textSelection(.enabled)
                    Button("Use a different email") { path = screen == .verify ? [] : [.reset] }.disabled(busy)
                }
            }
            Section {
                if screen != .verify && screen != .resetConfirm {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .email(screen))
                        .submitLabel(screen == .reset ? .send : .next)
                        .onSubmit { if screen == .reset { submitIfReady(screen) } else { focus = .password(screen) } }
                        .accessibilityIdentifier("auth.email")
                    if editedEmail && !email.isEmpty && !AuthInput.validEmail(normalizedEmail) {
                        Text("Enter a valid email address.").font(.footnote).foregroundStyle(.red)
                    }
                }
                if screen == .signIn || screen == .signUp || screen == .resetConfirm {
                    SecureField(screen == .resetConfirm ? String(localized: "New password") : String(localized: "Password"), text: $password)
                        .textContentType(screen == .signIn ? .password : .newPassword).focused($focus, equals: .password(screen))
                        .submitLabel(screen == .signUp ? .next : screen == .resetConfirm ? .next : .go)
                        .onSubmit {
                            if screen == .signUp { focus = .nickname }
                            else if screen == .resetConfirm { focus = .code(screen) }
                            else { submitIfReady(screen) }
                        }.accessibilityIdentifier("auth.password")
                    if screen != .signIn && editedPassword && !password.isEmpty && !AuthInput.validNewPassword(password) {
                        Text("Your password does not meet the requirements below.").font(.footnote).foregroundStyle(.red)
                    }
                }
                if screen == .verify || screen == .resetConfirm {
                    TextField("Verification code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        .focused($focus, equals: .code(screen))
                        .onChange(of: code) { _, value in code = String(value.filter { "0123456789".contains($0) }.prefix(6)) }
                }
            } header: {
                if screen == .signUp { Text("Account details") }
                else if screen == .verify { Text("Verification code") }
                else if screen == .resetConfirm { Text("New password and code") }
            } footer: {
                if screen == .signUp || screen == .resetConfirm {
                    Text("Use at least 8 characters with uppercase, lowercase, a number and a symbol.")
                } else if screen == .verify { Text("Enter the 6-digit code from your email.") }
            }
            .disabled(busy)

            if screen == .signUp {
                Section {
                    TextField("Nickname", text: $nickname).textContentType(.nickname).focused($focus, equals: .nickname).submitLabel(.next)
                        .onSubmit { focus = chinese ? .familyName : .givenName }
                    if chinese { familyField; givenField } else { givenField; familyField }
                    Picker("Gender", selection: $gender) {
                        Text("Prefer not to say / Other").tag("Other")
                        Text("Female").tag("Female"); Text("Male").tag("Male")
                    }
                } header: { Text("Your details") }
                footer: { Text("These fields are required by your PinHaoYun account. You can choose not to disclose your gender.") }
                .disabled(busy)
                Section("Your agreement") {
                    policyLinks
                    Toggle("I agree to the terms and have read the privacy notice.", isOn: $agreed).disabled(policy == nil || busy)
                }
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("auth.error") } }
            if let feedback, feedback.mode == screen { Section { Text(feedback.text).foregroundStyle(.secondary) } }
            if screen == .signIn {
                Section {
                    primaryButton(screen).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }
            if screen == .verify || screen == .resetConfirm {
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let seconds = max(0, Int(resendAfter.timeIntervalSince(timeline.date).rounded(.up)))
                        Button { resend(screen) } label: {
                            HStack { Text("Send a new code"); Spacer(); if resending { ProgressView() } }
                        }.disabled(busy || seconds > 0)
                        if seconds > 0 { Text(String(format: String(localized: "Resend available in %lld seconds."), Int64(seconds))).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            if screen == .signIn {
                Section {
                    NavigationLink("Create an account", value: Mode.signUp)
                    NavigationLink("Forgot password?", value: Mode.reset)
                    if api.hasSavedDeletionReceipt { Button("Check account deletion") { api.restoreReceipt() } }
                }.disabled(busy)
                Section { policyLinks
                    Text("Invited beta · Keep an independent copy of important originals.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title(screen)).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy && screen != .signIn)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if screen != .signIn { primaryButton(screen).padding(.horizontal).padding(.vertical, 8).background(.bar) }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } } }
    }

    private func primaryButton(_ screen: Mode) -> some View {
        Button { submit(screen) } label: {
            HStack { Spacer(); Text(actionTitle(screen)); if busy && !resending { ProgressView().tint(.white) }; Spacer() }.frame(minHeight: 32)
        }.buttonStyle(.borderedProminent).disabled(busy || !canSubmit(screen)).accessibilityIdentifier("auth.submit")
    }

    private var chinese: Bool { Locale.preferredLanguages.first?.hasPrefix("zh") == true }
    private var givenField: some View {
        TextField("Given name", text: $givenName).textContentType(.givenName).focused($focus, equals: .givenName).submitLabel(chinese ? .done : .next)
            .onSubmit { focus = chinese ? nil : .familyName }
    }
    private var familyField: some View {
        TextField("Family name", text: $familyName).textContentType(.familyName).focused($focus, equals: .familyName).submitLabel(chinese ? .next : .done)
            .onSubmit { focus = chinese ? .givenName : nil }
    }
    @ViewBuilder private var policyLinks: some View {
        if let policy {
            Button("Terms of use") { legal = PolicySheet(kind: .terms, document: policy) }
            Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: policy) }
            PolicyVersionView(document: policy)
        } else if loadingPolicy { ProgressView("Loading terms and privacy notice") }
        if let policyError {
            Text(policyError).font(.footnote).foregroundStyle(.red)
            Button("Reload terms and privacy notice") { Task { await loadPolicies() } }.disabled(loadingPolicy)
        }
    }
    private func canSubmit(_ screen: Mode) -> Bool {
        guard AuthInput.validEmail(normalizedEmail) else { return false }
        switch screen {
        case .signIn: return !password.isEmpty
        case .signUp: return AuthInput.validNewPassword(password) && [nickname, givenName, familyName].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && agreed && policy != nil
        case .verify: return code.count == 6
        case .reset: return true
        case .resetConfirm: return code.count == 6 && AuthInput.validNewPassword(password)
        }
    }
    private func title(_ screen: Mode) -> String {
        switch screen { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create an account"); case .verify: String(localized: "Verify your email"); case .reset: String(localized: "Reset password"); case .resetConfirm: String(localized: "Set a new password") }
    }
    private func actionTitle(_ screen: Mode) -> String {
        switch screen { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create account"); case .verify: String(localized: "Verify email"); case .reset: String(localized: "Send reset code"); case .resetConfirm: String(localized: "Save new password") }
    }
    private func loadPolicies() async {
        guard !loadingPolicy else { return }
        loadingPolicy = true; policyError = nil
        defer { loadingPolicy = false }
        do { policy = try await api.request("/api/mobile/policies", authenticated: false) }
        catch { if !Task.isCancelled { policyError = error.localizedDescription } }
    }
    private func submitIfReady(_ screen: Mode) { if !busy && canSubmit(screen) { submit(screen) } }
    private func submit(_ screen: Mode) {
        guard !busy && canSubmit(screen) else { return }
        busy = true; focus = nil; error = nil; feedback = nil
        let address = normalizedEmail, secret = password, verificationCode = code
        Task {
            defer { busy = false }
            do {
                switch screen {
                case .signIn: try await api.signIn(email: address, password: secret); password = ""
                case .signUp:
                    guard let policy else { throw URLError(.cannotLoadFromNetwork) }
                    var body = APIClient.consentBody(policy)
                    body.merge(["email": address, "password": secret, "preferredUsername": nickname.trimmingCharacters(in: .whitespacesAndNewlines), "givenName": givenName.trimmingCharacters(in: .whitespacesAndNewlines), "familyName": familyName.trimmingCharacters(in: .whitespacesAndNewlines), "gender": gender]) { _, new in new }
                    let _: OKResponse = try await api.request("/api/mobile/auth/sign-up", method: "POST", body: body, authenticated: false)
                    resendAfter = .now.addingTimeInterval(30); path = [.verify]
                case .verify:
                    let _: OKResponse = try await api.request("/api/mobile/auth/confirm-sign-up", method: "POST", body: ["email": address, "code": verificationCode], authenticated: false)
                    feedback = (.signIn, String(localized: "Email verified. You can now sign in.")); path = []
                case .reset:
                    let _: OKResponse = try await api.request("/api/mobile/auth/forgot-password", method: "POST", body: ["email": address], authenticated: false)
                    resendAfter = .now.addingTimeInterval(30); path = [.reset, .resetConfirm]
                case .resetConfirm:
                    let _: OKResponse = try await api.request("/api/mobile/auth/confirm-forgot-password", method: "POST", body: ["email": address, "code": verificationCode, "password": secret], authenticated: false)
                    feedback = (.signIn, String(localized: "Password updated. Sign in with your new password.")); path = []
                }
            } catch {
                if (error as? APIError)?.code == "UserNotConfirmedException" { path = [.verify] }
                else if screen == .signIn && (error as? APIError)?.code == "NotAuthorizedException" { self.error = String(localized: "Email or password is incorrect.") }
                else { self.error = error.localizedDescription }
            }
        }
    }
    private func resend(_ screen: Mode) {
        guard !busy, resendAfter <= .now else { return }
        busy = true; resending = true; error = nil
        Task {
            defer { busy = false; resending = false }
            do {
                let endpoint = screen == .verify ? "/api/mobile/auth/resend-code" : "/api/mobile/auth/forgot-password"
                let _: OKResponse = try await api.request(endpoint, method: "POST", body: ["email": normalizedEmail], authenticated: false)
                resendAfter = .now.addingTimeInterval(30); feedback = (screen, String(localized: "A new code has been sent."))
            } catch { self.error = error.localizedDescription }
        }
    }
}

enum AuthInput {
    static func validEmail(_ value: String) -> Bool {
        value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    static func validNewPassword(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        return value.count >= 8 && scalars.contains(where: CharacterSet.uppercaseLetters.contains)
            && scalars.contains(where: CharacterSet.lowercaseLetters.contains)
            && scalars.contains(where: CharacterSet.decimalDigits.contains)
            && scalars.contains { !CharacterSet.alphanumerics.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
