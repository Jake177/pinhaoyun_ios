import SwiftUI

struct PolicySheet: Identifiable {
    enum Kind { case terms, privacy }
    let kind: Kind
    let document: PolicyDocument
    var id: String { kind == .terms ? "terms" : "privacy" }
}
struct PolicyTextView: View {
    let sheet: PolicySheet
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(sheet.kind == .terms ? sheet.document.termsText : sheet.document.privacyText)
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
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
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Before you continue").font(.title2.bold())
                    Text("Please review the current terms and privacy notice for your PinHaoYun account.")
                }
                if let policy {
                    Section {
                        Button("Terms of use") { legal = PolicySheet(kind: .terms, document: policy) }
                        Button("Privacy notice") { legal = PolicySheet(kind: .privacy, document: policy) }
                        Toggle("I agree to the terms and have read the privacy notice.", isOn: $agreed)
                    }
                }
                if loadingPolicy { Section { ProgressView("Loading terms and privacy notice") } }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Try again") { Task { await loadPolicy() } }.disabled(loadingPolicy) } }
                Section {
                    Button(action: accept) { HStack { Text("Agree and continue"); Spacer(); if busy { ProgressView() } } }
                        .disabled(!agreed || policy == nil || busy)
                    Button("Sign out", role: .cancel) { Task { await api.signOut() } }
                }
            }
            .navigationTitle("Your account")
            .sheet(item: $legal) { PolicyTextView(sheet: $0) }
            .task { await loadPolicy() }
        }
    }
    private func loadPolicy() async {
        loadingPolicy = true; error = nil; agreed = false
        defer { loadingPolicy = false }
        do { policy = try await api.request("/api/mobile/policies", authenticated: false) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func accept() {
        guard let policy else { return }
        busy = true
        Task { do { try await api.accept(policy) } catch { self.error = error.localizedDescription }; busy = false }
    }
}
struct DeletionReceiptView: View {
    @Environment(APIClient.self) private var api
    @State private var status: DeletionStatus?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(status?.state == "COMPLETE" ? String(localized: "Account deleted") : status != nil || api.deletionReceipt?.state != "REQUESTING" ? String(localized: "Account deletion requested") : String(localized: "Checking deletion request"), systemImage: status?.state == "COMPLETE" ? "checkmark.circle" : "clock")
                        .font(.title2).foregroundStyle(.tint)
                    Text("Cloud data will be deleted within 30 days. Photos on your device are kept.")
                    if let receipt = api.deletionReceipt, (status != nil || receipt.state != "REQUESTING"), let deadline = MediaItem.parseDate(receipt.deleteBy) { LabeledContent("Delete by", value: deadline.formatted(date: .abbreviated, time: .shortened)) }
                    if let completed = status?.completedAt, let date = MediaItem.parseDate(completed) { LabeledContent("Completed", value: date.formatted(date: .abbreviated, time: .shortened)) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Button("Check deletion status", action: refresh); Button("Return to sign in") { api.dismissReceipt() } }
            }
            .navigationTitle("Account deletion")
            .task { await load() }
            .refreshable { await load() }
        }
    }
    private func refresh() { Task { await load() } }
    private func load() async { do { status = try await api.deletionStatus(); error = nil } catch { self.error = error.localizedDescription } }
}
