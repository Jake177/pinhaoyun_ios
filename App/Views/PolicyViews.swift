import SwiftUI

struct PolicySheet: Identifiable {
    enum Kind { case terms, privacy }
    let kind: Kind
    let document: PolicyDocument
    var id: String { kind == .terms ? "terms" : "privacy" }
}
struct PolicyVersionView: View {
    let document: PolicyDocument
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if document.isDraft { Label("Testing draft", systemImage: "doc.text") }
            Text(String(format: String(localized: "Version: %@"), document.version)).textSelection(.enabled)
        }.font(.footnote).foregroundStyle(.secondary)
    }
}
struct PolicyTextView: View {
    let sheet: PolicySheet
    @Environment(\.dismiss) private var dismiss
    private var reading: PolicyReadingText? {
        let texts = sheet.kind == .terms ? sheet.document.reading?.terms : sheet.document.reading?.privacy
        return texts?[sheet.document.language] ?? texts?["en"]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PolicyVersionView(document: sheet.document)
                    if let reading {
                        Text(reading.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        ForEach(Array(reading.sections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title).font(.headline).accessibilityAddTraits(.isHeader)
                                Text(section.text).font(.body)
                            }
                        }
                    } else {
                        Text(sheet.kind == .terms ? sheet.document.termsText : sheet.document.privacyText).font(.body)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
            }
            .navigationTitle(sheet.kind == .terms ? String(localized: "Terms of use") : String(localized: "Privacy notice"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct ConsentView: View {
    @Environment(APIClient.self) private var api
    @State private var policy: PolicyDocument?
    @State private var legal: PolicySheet?
    @State private var agreed = false
    @State private var busy = false
    @State private var loadingPolicy = false
    @State private var policyError: String?
    @State private var submissionError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Please review the current terms and privacy notice for your PinHaoYun account.") }
                if let policy {
                    Section("Your agreement") {
                        Button("Terms of use") { legal = PolicySheet(kind: .terms, document: policy) }
                        Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: policy) }
                        PolicyVersionView(document: policy)
                        Toggle("I agree to the terms and have read the privacy notice.", isOn: $agreed).disabled(busy)
                    }
                }
                if loadingPolicy { Section { ProgressView("Loading terms and privacy notice") } }
                if let policyError {
                    Section { Label(policyError, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        Button("Reload terms and privacy notice") { Task { await loadPolicy() } }.disabled(loadingPolicy || busy)
                    }
                }
                if let submissionError {
                    Section { Label(submissionError, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        Button("Retry agreement submission", action: accept).disabled(busy || !agreed)
                    }
                }
                Section {
                    Button(action: accept) { HStack { Spacer(); Text("Agree and continue"); if busy { ProgressView().tint(.white) }; Spacer() }.frame(minHeight: 32) }
                        .buttonStyle(.borderedProminent).disabled(!agreed || policy == nil || busy || loadingPolicy)
                        .listRowBackground(Color.clear)
                    Button("Sign out", role: .cancel) { Task { await api.signOut() } }.disabled(busy)
                }
            }.navigationTitle("Review terms").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $legal) { PolicyTextView(sheet: $0) }
                .task { await loadPolicy() }
        }
    }
    private func loadPolicy() async {
        guard !loadingPolicy else { return }
        loadingPolicy = true; policyError = nil; agreed = false
        defer { loadingPolicy = false }
        do { policy = try await api.request("/api/mobile/policies", authenticated: false) }
        catch { if !Task.isCancelled { policyError = error.localizedDescription } }
    }
    private func accept() {
        guard let policy, agreed, !busy else { return }
        busy = true; submissionError = nil
        Task { defer { busy = false }; do { try await api.accept(policy) } catch { submissionError = error.localizedDescription } }
    }
}
struct DeletionReceiptView: View {
    @Environment(APIClient.self) private var api
    @State private var status: DeletionStatus?
    @State private var error: String?
    @State private var checking = false
    @State private var lastChecked: Date?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(status?.state == "COMPLETE" ? String(localized: "Account deleted") : status != nil || api.deletionReceipt?.state != "REQUESTING" ? String(localized: "Account deletion requested") : String(localized: "Checking deletion request"), systemImage: status?.state == "COMPLETE" ? "checkmark.circle" : "clock")
                        .font(.title2).foregroundStyle(.tint)
                    Text(status?.state == "COMPLETE" ? String(localized: "Your cloud account data has been deleted. Photos on your device are kept.") : String(localized: "Cloud data will be deleted within 30 days. Photos on your device are kept."))
                    if let receipt = api.deletionReceipt, (status != nil || receipt.state != "REQUESTING"), let deadline = MediaItem.parseDate(status?.deleteBy ?? receipt.deleteBy) {
                        LabeledContent("Delete by", value: deadline.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let completed = status?.completedAt, let date = MediaItem.parseDate(completed) { LabeledContent("Completed", value: date.formatted(date: .abbreviated, time: .shortened)) }
                    if let lastChecked { LabeledContent("Last checked", value: lastChecked.formatted(date: .abbreviated, time: .shortened)) }
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
                Section {
                    Button(action: refresh) { HStack { Text("Check deletion status"); Spacer(); if checking { ProgressView() } } }.disabled(checking)
                    Button("Return to sign in") { api.dismissReceipt() }
                }
            }.navigationTitle("Account deletion").navigationBarTitleDisplayMode(.inline)
                .task { await load() }.refreshable { await load() }
        }
    }
    private func refresh() { Task { await load() } }
    private func load() async {
        guard !checking else { return }
        checking = true; error = nil
        defer { checking = false }
        do { status = try await api.deletionStatus(); lastChecked = .now }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
