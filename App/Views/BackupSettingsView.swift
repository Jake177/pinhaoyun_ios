import SwiftUI
import Photos

struct BackupSettingsView: View {
    @Environment(BackupManager.self) private var backup
    @State private var confirmingEnable = false
    @State private var confirmingAll = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Group {
            if let settings = backup.settings {
                @Bindable var settings = settings
                Form {
                    Section {
                        Toggle("Automatic backup", isOn: Binding(get: { settings.enabled }, set: { enabled in
                            if enabled { confirmingEnable = true } else { Task { await backup.pause() } }
                        }))
                        BackupStatusView()
                    } footer: { Text("This device backs up to the signed-in account. Deleting from Photos does not delete cloud copies.") }
                    Section("Backup content") {
                        Picker("Photos to back up", selection: Binding(get: { settings.scope }, set: { value in
                            if value == "all", settings.enabled, settings.scope == "new" { confirmingAll = true }
                            else { settings.scope = value; backup.settingsChanged() }
                        })) {
                            Text("Only new photos").tag("new")
                            Text("All accessible photos").tag("all")
                        }
                        Toggle("Include videos", isOn: $settings.videos).onChange(of: settings.videos) { backup.settingsChanged() }
                        Text("Live Photos always include their motion. Hidden photos and unsupported originals are skipped.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Network") {
                        Toggle("Allow cellular data", isOn: $settings.cellular).onChange(of: settings.cellular) { backup.settingsChanged() }
                        Text(settings.cellular ? String(localized: "Originals may use Wi-Fi and cellular data, including downloads from iCloud.") : String(localized: "Originals wait for Wi-Fi, including downloads from iCloud.")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Backup time") {
                        Toggle("Use a daily time window", isOn: $settings.windowEnabled).onChange(of: settings.windowEnabled) { backup.settingsChanged() }
                        if settings.windowEnabled {
                            DatePicker("Start", selection: minuteBinding(settings, start: true), displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: minuteBinding(settings, start: false), displayedComponents: .hourAndMinute)
                            if !backup.window.valid { Text("Choose different start and end times.").foregroundStyle(.red) }
                        }
                        Text("Uses your current local time, including travel and daylight saving. Started items may finish after the window ends.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Photos access") {
                        Text(backup.permission == .limited ? String(localized: "Only your selected photos are accessible.") : backup.hasPermission ? String(localized: "Photos access is available.") : String(localized: "Allow Photos access to resume backup"))
                        if backup.permission == .limited { Button("Manage selected photos", action: manageLimitedPhotos) }
                        if backup.permission == .limited { Text("New camera photos need to be added to your selection, or you can allow full Photos access in Settings.").font(.footnote).foregroundStyle(.secondary) }
                        if !backup.hasPermission || backup.permission == .limited { Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
                    }
                    Section {
                        Button("Check for new photos") { backup.check() }.disabled(!settings.enabled || backup.scanning)
                        Button("Retry backup issues") { backup.retryIssues() }.disabled(!settings.enabled)
                        if let date = settings.lastCheckedAt { LabeledContent("Last checked", value: date.formatted(date: .abbreviated, time: .shortened)) }
                        if busy { ProgressView("Preparing automatic backup") }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    let issues = backup.assets.filter { ["failed", "skipped"].contains($0.state) }
                    if !issues.isEmpty {
                        Section("Backup issues") {
                            ForEach(Array(issues.prefix(20))) { asset in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.state == "skipped" ? String(localized: "Skipped") : String(localized: "Needs attention")).font(.subheadline)
                                    if let message = asset.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    Section {
                        Text("iOS decides when background work runs. Exact start times are not guaranteed. Reopen the app after force quitting to resume backup.").font(.footnote).foregroundStyle(.secondary)
                        Text("Deleted cloud copies are not automatically uploaded again. Select an original manually if you want to upload it again.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let file = backup.diagnosticsURL {
                        Section("Beta diagnostics") {
                            ShareLink("Export backup diagnostics", item: file)
                            Text("Includes device type, times, network state and backup counts. No photos or login credentials.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.disabled(busy)
                    .confirmationDialog("Enable automatic backup?", isPresented: $confirmingEnable, titleVisibility: .visible) {
                        Button("Enable backup") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do { try await backup.enable() } catch { self.error = error.localizedDescription }
                            }
                        }.disabled(!backup.window.valid)
                    } message: {
                        Text(settings.scope == "new" ? String(localized: "Only photos newly accessible after activation will be backed up, including older photos you import later. Your current photos are kept on this device.") : String(localized: "All accessible photos will be considered for backup. This may use significant cloud storage and network data."))
                    }
                    .confirmationDialog("Include existing photos?", isPresented: $confirmingAll, titleVisibility: .visible) {
                        Button("Back up existing photos") { settings.scope = "all"; backup.settingsChanged() }
                    } message: { Text("All accessible photos will be considered for backup. This may use significant cloud storage and network data.") }
            } else { ProgressView("Loading your account") }
        }.navigationTitle("Automatic backup").navigationBarTitleDisplayMode(.inline)
    }
    private func minuteBinding(_ settings: BackupSettings, start: Bool) -> Binding<Date> {
        Binding(get: {
            let minute = start ? settings.startMinute : settings.endMinute
            return Calendar.autoupdatingCurrent.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: minute / 60, minute: minute % 60)) ?? .now
        }, set: { date in
            let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if start { settings.startMinute = minute } else { settings.endMinute = minute }
            backup.settingsChanged()
        })
    }
    private func manageLimitedPhotos() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = controller.presentedViewController { controller = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

struct BackupStatusView: View {
    @Environment(BackupManager.self) private var backup
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(backup.status).font(.subheadline)
            if backup.settings?.enabled == true {
                let records = backup.eligibleAssets
                Text(String(format: String(localized: "%lld backed up · %lld pending · %lld need attention"), Int64(records.filter { $0.state == "completed" }.count), Int64(records.filter { ["pending", "queued"].contains($0.state) }.count), Int64(records.filter { $0.state == "failed" }.count))).font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
