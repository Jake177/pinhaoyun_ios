import SwiftUI

struct AuthView: View {
    enum Mode: String { case signIn, signUp, verify, reset, resetConfirm }
    @Environment(APIClient.self) private var api
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var gender = "Other"
    @State private var code = ""
    @State private var agreed = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var policy: PolicyDocument?
    @State private var legal: PolicySheet?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image("BrandMark").resizable().scaledToFit().frame(width: 64, height: 64).accessibilityHidden(true)
                        Text("PinHaoYun").font(.largeTitle.bold())
                        Text("Your photos and videos, together.").font(.body).foregroundStyle(.secondary)
                    }.padding(.vertical, 16)
                }.listRowBackground(Color.clear)
                Section(title) {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth.email")
                    if [.signIn, .signUp, .resetConfirm].contains(mode) {
                        SecureField(mode == .resetConfirm ? String(localized: "New password") : String(localized: "Password"), text: $password).textContentType(mode == .signIn ? .password : .newPassword).accessibilityIdentifier("auth.password").submitLabel(.go).onSubmit { if mode == .signIn && canSubmit { submit() } }
                    }
                    if [.verify, .resetConfirm].contains(mode) { TextField("Verification code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad) }
                    if mode == .signUp {
                        TextField("Nickname", text: $nickname).textContentType(.nickname)
                        TextField("Given name", text: $givenName).textContentType(.givenName)
                        TextField("Family name", text: $familyName).textContentType(.familyName)
                        Picker("Gender", selection: $gender) {
                            Text("Prefer not to say / Other").tag("Other")
                            Text("Female").tag("Female"); Text("Male").tag("Male")
                        }
                    }
                }
                if mode == .signUp || mode == .resetConfirm {
                    Section { Text("Use at least 8 characters with uppercase, lowercase, a number and a symbol.").font(.footnote).foregroundStyle(.secondary) }
                }
                if mode == .signUp {
                    Section { Toggle("I agree to the terms and have read the privacy notice.", isOn: $agreed) }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("auth.error") } }
                if let notice { Section { Text(notice).foregroundStyle(.secondary) } }
                Section {
                    Button(action: submit) { HStack { Text(actionTitle); Spacer(); if busy { ProgressView() } } }.disabled(busy || !canSubmit).accessibilityIdentifier("auth.submit")
                    if mode == .signIn {
                        Button("Create an account") { change(.signUp) }
                        Button("Forgot password?") { password = ""; change(.reset) }
                    } else {
                        if mode == .verify { Button("Send a new code", action: resend).disabled(busy) }
                        Button("Back to sign in") { change(.signIn) }
                    }
                }
                Section {
                    if let policy {
                        Button("Terms of use") { legal = PolicySheet(kind: .terms, document: policy) }
                        Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: policy) }
                    } else { Button("Load terms and privacy notice") { Task { await loadPolicies() } } }
                    Text("Invited beta · Keep an independent copy of important originals.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $legal) { PolicyTextView(sheet: $0) }
            .task { await loadPolicies() }
        }
    }
    private var canSubmit: Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch mode {
        case .signIn: return !password.isEmpty
        case .signUp: return !password.isEmpty && !nickname.isEmpty && !givenName.isEmpty && !familyName.isEmpty && agreed && policy != nil
        case .verify: return !code.isEmpty
        case .reset: return true
        case .resetConfirm: return !code.isEmpty && !password.isEmpty
        }
    }
    private var title: String {
        switch mode { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create an account"); case .verify: String(localized: "Verify your email"); case .reset: String(localized: "Reset password"); case .resetConfirm: String(localized: "Set a new password") }
    }
    private var actionTitle: String {
        switch mode { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create account"); case .verify: String(localized: "Verify email"); case .reset: String(localized: "Send reset code"); case .resetConfirm: String(localized: "Save new password") }
    }
    private func change(_ value: Mode) { mode = value; error = nil; notice = nil; code = "" }
    private func loadPolicies() async { do { policy = try await api.request("/api/mobile/policies", authenticated: false) } catch { self.error = error.localizedDescription } }
    private func submit() {
        busy = true; error = nil; notice = nil
        Task {
            do {
                switch mode {
                case .signIn: try await api.signIn(email: email, password: password); password = ""
                case .signUp:
                    guard let policy else { throw URLError(.cannotLoadFromNetwork) }
                    var body = APIClient.consentBody(policy)
                    body.merge(["email": email, "password": password, "preferredUsername": nickname, "givenName": givenName, "familyName": familyName, "gender": gender]) { _, new in new }
                    let _: OKResponse = try await api.request("/api/mobile/auth/sign-up", method: "POST", body: body, authenticated: false)
                    change(.verify); notice = String(localized: "Enter the code sent to your email.")
                case .verify:
                    let _: OKResponse = try await api.request("/api/mobile/auth/confirm-sign-up", method: "POST", body: ["email": email, "code": code], authenticated: false)
                    change(.signIn); notice = String(localized: "Email verified. You can now sign in.")
                case .reset:
                    let _: OKResponse = try await api.request("/api/mobile/auth/forgot-password", method: "POST", body: ["email": email], authenticated: false)
                    change(.resetConfirm); notice = String(localized: "Enter the code sent to your email.")
                case .resetConfirm:
                    let _: OKResponse = try await api.request("/api/mobile/auth/confirm-forgot-password", method: "POST", body: ["email": email, "code": code, "password": password], authenticated: false)
                    password = ""; change(.signIn); notice = String(localized: "Password updated. Sign in with your new password.")
                }
            } catch {
                if (error as? APIError)?.code == "UserNotConfirmedException" { change(.verify) }
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
    private func resend() {
        busy = true
        Task { do { let _: OKResponse = try await api.request("/api/mobile/auth/resend-code", method: "POST", body: ["email": email], authenticated: false); notice = String(localized: "A new code has been sent."); error = nil } catch { self.error = error.localizedDescription }; busy = false }
    }
}
