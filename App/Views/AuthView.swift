import SwiftUI

struct AuthView: View {
    enum Mode: Hashable { case signIn, signUp, verify, reset, resetCode, resetConfirm }
    private enum Field: Hashable { case email(Mode), password(Mode), code(Mode), confirmation, nickname, givenName, familyName }
    @Environment(APIClient.self) private var api
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var path: [Mode] = []
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationPassword = ""
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
    @State private var editedConfirmation = false
    @State private var resetCodeError: String?
    @State private var resendAfter = Date.distantPast
    @FocusState private var focus: Field?
    @AccessibilityFocusState private var signInErrorFocused: Bool
    private var mode: Mode { path.last ?? .signIn }
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            signIn
                .navigationDestination(for: Mode.self) { form($0) }
        }
        .sheet(item: $legal) { PolicyTextView(sheet: $0) }
        .task { await loadPolicies() }
        .onChange(of: path) { _, _ in
            focus = nil; error = nil; password = ""; confirmationPassword = ""
            if mode != .resetCode && mode != .resetConfirm { code = "" }
            if mode != .resetCode { resetCodeError = nil }
            editedEmail = false; editedPassword = false; editedConfirmation = false; agreed = false
            if feedback?.mode != mode { feedback = nil }
        }
        .onChange(of: focus) { old, _ in
            if case .email(_)? = old { editedEmail = true }
            if case .password(_)? = old { editedPassword = true }
            if old == .confirmation { editedConfirmation = true }
        }
        .onChange(of: error) { _, message in
            if message != nil && mode == .signIn { signInErrorFocused = true }
        }
    }

    private var signIn: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 16) {
                        if focus == nil && !dynamicTypeSize.isAccessibilitySize && geometry.size.height > 400 {
                            Image("LoginMemories").resizable().scaledToFit()
                                .frame(height: min(216, geometry.size.height * 0.28))
                                .frame(maxWidth: .infinity).accessibilityHidden(true)
                        }
                        signInBrand
                        if focus == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your memories,\nwell kept.").font(.largeTitle.bold())
                                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                                Text("Photos, videos and Live Photos, together.").font(.subheadline).foregroundStyle(Color.primary.opacity(0.7))
                                    .fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.bottom, 24)

                    VStack(alignment: .leading, spacing: 12) {
                        signInFields
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("auth.error").accessibilityFocused($signInErrorFocused)
                        }
                        if let feedback, feedback.mode == .signIn {
                            Text(feedback.text).font(.subheadline).foregroundStyle(Color.primary.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        primaryButton(.signIn).controlSize(.large).buttonBorderShape(.capsule)
                        signInSecondaryActions
                        if api.hasSavedDeletionReceipt {
                            Button("Check account deletion") { api.restoreReceipt() }.frame(minHeight: 44).disabled(busy)
                        }
                    }
                    Spacer(minLength: 16)
                    signInPolicies
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil } } }
    }

    private var signInBrand: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { brandMark; brandName.multilineTextAlignment(.center).frame(maxWidth: .infinity) }
            } else {
                HStack(spacing: 12) { brandMark; brandName }
            }
        }.frame(maxWidth: .infinity)
    }
    private var brandMark: some View {
        Image("BrandMark").resizable().scaledToFit().frame(width: 56, height: 56).accessibilityHidden(true)
    }
    private var brandName: some View {
        Text("PinHaoYun").font(.title.bold()).fixedSize(horizontal: false, vertical: true)
    }

    private var signInFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Email").font(.caption).accessibilityHidden(true)
                    emailInput(.signIn).frame(minHeight: 44)
                }.padding(.vertical, 12)
                signInEmailError
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password").font(.caption).accessibilityHidden(true)
                    passwordInput(.signIn).frame(minHeight: 44)
                }.padding(.vertical, 12)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    GridRow {
                        Text("Email").accessibilityHidden(true)
                        emailInput(.signIn).frame(minHeight: 52)
                    }
                    signInEmailError.gridCellColumns(2)
                    Divider().gridCellColumns(2).gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("Password").accessibilityHidden(true)
                        passwordInput(.signIn).frame(minHeight: 52)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .disabled(busy)
    }
    @ViewBuilder private var signInEmailError: some View {
        if editedEmail && !email.isEmpty && !AuthInput.validEmail(normalizedEmail) {
            Text("Enter a valid email address.").font(.footnote).foregroundStyle(.red).padding(.bottom, 12)
        }
    }
    private var signInSecondaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                registrationLink.fixedSize()
                Spacer(minLength: 16)
                resetLink.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) { registrationLink; resetLink }
        }.disabled(busy)
    }
    private var registrationLink: some View {
        NavigationLink("Create an account", value: Mode.signUp).frame(minHeight: 44).accessibilityIdentifier("auth.signUp")
    }
    private var resetLink: some View {
        NavigationLink("Forgot password?", value: Mode.reset).frame(minHeight: 44).accessibilityIdentifier("auth.reset")
    }
    private var signInPolicies: some View {
        VStack(spacing: 0) {
            if let policy {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { termsLink(policy).fixedSize(); privacyLink(policy).fixedSize() }
                    VStack(spacing: 0) { termsLink(policy); privacyLink(policy) }
                }
            } else if loadingPolicy {
                ProgressView("Loading terms and privacy notice").font(.footnote).padding(.vertical, 12)
            }
            if let policyError {
                Text(policyError).font(.footnote).foregroundStyle(.red)
                Button("Reload terms and privacy notice") { Task { await loadPolicies() } }.frame(minHeight: 44).disabled(loadingPolicy)
            }
            Text("Invited beta · Keep an independent copy of important originals.").font(.caption).foregroundStyle(Color.primary.opacity(0.7))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity)
    }
    private func termsLink(_ document: PolicyDocument) -> some View {
        Button("Terms of use") { legal = PolicySheet(kind: .terms, document: document) }
            .font(.footnote).frame(minHeight: 44).accessibilityIdentifier("auth.terms")
    }
    private func privacyLink(_ document: PolicyDocument) -> some View {
        Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: document) }
            .font(.footnote).frame(minHeight: 44).accessibilityIdentifier("auth.privacy")
    }
    private func emailInput(_ screen: Mode) -> some View {
        TextField(screen == .signIn ? "name@example.com" : String(localized: "Email"), text: $email,
                  prompt: Text(screen == .signIn ? "name@example.com" : String(localized: "Email")).foregroundStyle(Color.primary.opacity(0.7)))
            .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            .focused($focus, equals: .email(screen)).submitLabel(screen == .reset ? .send : .next)
            .onSubmit { if screen == .reset { submitIfReady(screen) } else { focus = .password(screen) } }
            .accessibilityLabel(Text("Email")).accessibilityIdentifier("auth.email")
    }
    private func passwordInput(_ screen: Mode) -> some View {
        let placeholder = screen == .resetConfirm ? String(localized: "New password") : screen == .signIn ? String(localized: "Enter password") : String(localized: "Password")
        return SecureField(placeholder, text: $password, prompt: Text(placeholder).foregroundStyle(Color.primary.opacity(0.7)))
            .textContentType(screen == .signIn ? .password : .newPassword).focused($focus, equals: .password(screen))
            .submitLabel(screen == .signUp || screen == .resetConfirm ? .next : .go)
            .onSubmit {
                if screen == .signUp { focus = .nickname }
                else if screen == .resetConfirm { focus = .confirmation }
                else { submitIfReady(screen) }
            }
            .accessibilityLabel(Text(screen == .resetConfirm ? String(localized: "New password") : String(localized: "Password")))
            .accessibilityIdentifier("auth.password")
    }

    private func form(_ screen: Mode) -> some View {
        Form {
            if screen == .verify || screen == .resetCode {
                Section {
                    Text("A verification code was sent to")
                    Text(normalizedEmail).font(.headline).textSelection(.enabled)
                    Button("Use a different email") { path = screen == .verify ? [] : [.reset] }.disabled(busy)
                }
            }
            Section {
                if screen == .signUp || screen == .reset {
                    emailInput(screen)
                    if editedEmail && !email.isEmpty && !AuthInput.validEmail(normalizedEmail) {
                        Text("Enter a valid email address.").font(.footnote).foregroundStyle(.red)
                    }
                }
                if screen == .signUp || screen == .resetConfirm {
                    passwordInput(screen)
                    if editedPassword && !password.isEmpty && !AuthInput.validNewPassword(password) {
                        Text("Your password does not meet the requirements below.").font(.footnote).foregroundStyle(.red)
                    }
                }
                if screen == .resetConfirm {
                    SecureField("Confirm new password", text: $confirmationPassword)
                        .textContentType(.newPassword).focused($focus, equals: .confirmation).submitLabel(.go)
                        .onSubmit { editedConfirmation = true; submitIfReady(screen) }.accessibilityIdentifier("auth.confirmPassword")
                    if editedConfirmation && !confirmationPassword.isEmpty && password != confirmationPassword {
                        Text("The passwords do not match.").font(.footnote).foregroundStyle(.red)
                    }
                }
                if screen == .verify || screen == .resetCode {
                    TextField("Verification code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        .focused($focus, equals: .code(screen))
                        .onChange(of: code) { _, value in
                            code = String(value.filter { "0123456789".contains($0) }.prefix(6))
                            if !value.isEmpty { resetCodeError = nil }
                        }
                        .accessibilityIdentifier("auth.verificationCode")
                    if let resetCodeError, screen == .resetCode {
                        Label(resetCodeError, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("auth.resetCodeError")
                    }
                }
            } header: {
                if screen == .signUp { Text("Account details") }
                else if screen == .verify || screen == .resetCode { Text("Verification code") }
                else if screen == .resetConfirm { Text("Enter your new password twice.") }
            } footer: {
                if screen == .signUp || screen == .resetConfirm {
                    Text("Use at least 8 characters with uppercase, lowercase, a number and a symbol.")
                } else if screen == .verify || screen == .resetCode { Text("Enter the 6-digit code from your email.") }
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
            if screen == .verify || screen == .resetCode {
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
        }
        .navigationTitle(title(screen)).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
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
        case .resetCode: return code.count == 6
        case .resetConfirm: return code.count == 6 && AuthInput.validResetPassword(password, confirmation: confirmationPassword)
        }
    }
    private func title(_ screen: Mode) -> String {
        switch screen { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create an account"); case .verify: String(localized: "Verify your email"); case .reset: String(localized: "Reset password"); case .resetCode: String(localized: "Enter reset code"); case .resetConfirm: String(localized: "Set a new password") }
    }
    private func actionTitle(_ screen: Mode) -> String {
        switch screen { case .signIn: String(localized: "Sign in"); case .signUp: String(localized: "Create account"); case .verify: String(localized: "Verify email"); case .reset: String(localized: "Send reset code"); case .resetCode: String(localized: "Continue"); case .resetConfirm: String(localized: "Save new password") }
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
        if screen == .resetCode { path.append(.resetConfirm); return }
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
                    resendAfter = .now.addingTimeInterval(30); code = ""; path.append(.resetCode)
                case .resetCode: break
                case .resetConfirm:
                    let _: OKResponse = try await api.request("/api/mobile/auth/confirm-forgot-password", method: "POST", body: ["email": address, "code": verificationCode, "password": secret], authenticated: false)
                    feedback = (.signIn, String(localized: "Password updated. Sign in with your new password.")); path = []
                }
            } catch {
                if screen == .resetConfirm, ["CodeMismatchException", "ExpiredCodeException"].contains((error as? APIError)?.code ?? "") {
                    code = ""; resetCodeError = error.localizedDescription; path.removeLast()
                }
                else if (error as? APIError)?.code == "UserNotConfirmedException" { path = [.verify] }
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
                code = ""; resetCodeError = nil; resendAfter = .now.addingTimeInterval(30); feedback = (screen, String(localized: "A new code has been sent."))
            } catch { self.error = error.localizedDescription }
        }
    }
}

enum AuthInput {
    static func validResetPassword(_ value: String, confirmation: String) -> Bool { validNewPassword(value) && value == confirmation }
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
