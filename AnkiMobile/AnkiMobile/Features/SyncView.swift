//
//  SyncView.swift
//  AnkiMobile
//
//  Screen 5 — AnkiWeb Sync & Account. Mocked in v1: the two cloud actions
//  (Pull Decks, Sync Progress) run against MockCloudService, not a real server.
//

import SwiftUI
import SwiftData

private struct ActivityEntry: Identifiable {
    enum Kind { case progress, deck }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let time: String
}

/// Drives the Force Upload / Download conflict dialog when a normal sync can't reconcile.
private struct ConflictPrompt: Identifiable {
    let id = UUID()
    let reason: String
}

/// Drives the "you have unsynced reviews" warning before a Download replaces the collection.
private struct PullGuardPrompt: Identifiable {
    let id = UUID()
    let pending: Int
}

struct SyncView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("mediaSyncing") private var mediaSyncing = true

    @State private var isSyncing = false
    @State private var isPulling = false
    @State private var conflict: ConflictPrompt?
    @State private var pullGuard: PullGuardPrompt?
    @State private var status: SyncStatus?
    @State private var checkingStatus = false
    @State private var dbBytes = 0
    @State private var mediaBytes = 0
    @State private var mediaFiles = 0
    @State private var confirmPrune = false
    @State private var syncProgress: Double = 0
    @State private var syncStageText = ""
    @State private var lastSync = "Today at 09:37"
    @State private var activity: [ActivityEntry] = [
        ActivityEntry(kind: .progress, title: "Progress Synced",
                      detail: "42 reviews synced, scheduling intervals updated across 3 decks · 0.8s",
                      time: "09:37:12"),
        ActivityEntry(kind: .deck, title: "Deck Updated",
                      detail: "Medical :: Pharmacology · 8 new cards pulled from AnkiWeb · 1.4 MB",
                      time: "08:15:04"),
    ]

    /// Both cloud actions now run against the real AnkiWeb engine (V2.3): pull downloads
    /// the collection, sync pushes local review progress.
    private let engine: any SyncEngine = AnkiWebSyncEngine()
    @Environment(AuthController.self) private var auth

    // Login form
    @State private var loginUser = ""
    @State private var loginPassword = ""
    @State private var loginHost = AuthController.defaultHost
    @State private var isLoggingIn = false
    @State private var loginError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.spaceMd) {
                    if auth.isLoggedIn {
                        profileCard
                        statusCard
                        cloudActions
                        storageCard
                        activityCard
                        logoutButton
                    } else {
                        loginCard
                    }
                }
                .padding(.horizontal, Metrics.screenMargin)
                .padding(.vertical, Metrics.spaceMd)
            }
            .background(Palette.canvas.ignoresSafeArea())
            .navigationTitle("Sync & Account")
            .task(id: auth.isLoggedIn) { await refreshStatus() }
            .sheet(item: $conflict) { prompt in
                ConflictSheet(
                    reason: prompt.reason,
                    onDownload: { conflict = nil; performPull() },   // cloud wins: explicit, skip the guard
                    onUpload: { conflict = nil; forceUpload() },
                    onCancel: { conflict = nil }
                )
                .presentationDetents([.medium])
                .presentationBackground(Palette.canvas)
            }
            .alert("Unsynced Progress",
                   isPresented: Binding(get: { pullGuard != nil }, set: { if !$0 { pullGuard = nil } }),
                   presenting: pullGuard) { _ in
                Button("Sync First") { pullGuard = nil; syncThenPull() }
                Button("Download Anyway", role: .destructive) { pullGuard = nil; performPull() }
                Button("Cancel", role: .cancel) { pullGuard = nil }
            } message: { prompt in
                Text("You have \(prompt.pending) unsynced review\(prompt.pending == 1 ? "" : "s"). Downloading replaces this device's collection and will discard them.")
            }
        }
    }

    // MARK: Login

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceMd) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect to AnkiWeb")
                    .font(AppFont.headlineSm)
                    .foregroundStyle(Palette.textPrimary)
                Text("Log in to pull decks and sync your review progress.")
                    .font(AppFont.bodySm)
                    .foregroundStyle(Palette.textSecondary)
            }

            field(icon: "envelope", placeholder: "Email", text: $loginUser, secure: false)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            field(icon: "lock", placeholder: "Password", text: $loginPassword, secure: true)
            field(icon: "server.rack", placeholder: "Server", text: $loginHost, secure: false)
                .textInputAutocapitalization(.never)

            if let loginError {
                Text(loginError)
                    .font(AppFont.labelSm)
                    .foregroundStyle(Palette.critical)
            }

            Button(action: performLogin) {
                HStack(spacing: 8) {
                    if isLoggingIn {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .rotationEffect(.degrees(360))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoggingIn)
                    }
                    Text(isLoggingIn ? "Logging in…" : "Log In")
                }
                .font(AppFont.headlineSm)
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.touchComfortable)
                .background(Palette.primary, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            }
            .disabled(isLoggingIn)
        }
        .surfaceCard(cornerRadius: Metrics.radiusCard)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: Metrics.spaceSm) {
            Image(systemName: icon).foregroundStyle(Palette.textMuted).frame(width: 18)
            if secure {
                SecureField(placeholder, text: text).font(AppFont.bodyMd)
            } else {
                TextField(placeholder, text: text).font(AppFont.bodyMd).autocorrectionDisabled()
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Metrics.spaceSm)
        .frame(height: Metrics.touchMin)
        .background(Palette.surfaceLow, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: Profile

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack(spacing: Metrics.spaceSm) {
                Image(systemName: "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 44, height: 44)
                    .background(Palette.primary.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.credentials?.username ?? "Account")
                        .font(AppFont.headlineSm)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(Palette.success).frame(width: 6, height: 6)
                        Text("Connected · \(lastSync)")
                            .font(AppFont.labelSm)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
            }

            if isSyncing || isPulling {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(syncStageText).font(AppFont.monoSm).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Int(syncProgress * 100))%").font(AppFont.monoSm).foregroundStyle(Palette.textSecondary)
                    }
                    ProgressView(value: syncProgress)
                        .tint(isPulling ? Palette.primary : Palette.success)
                }
            }
        }
        .surfaceCard(cornerRadius: Metrics.radiusCard)
    }

    // MARK: Sync status (ahead / behind indicator)

    private var statusCard: some View {
        HStack(spacing: Metrics.spaceSm) {
            Image(systemName: statusIcon)
                .font(.system(size: 18))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(statusColor.opacity(0.15), in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(AppFont.labelMd)
                    .foregroundStyle(Palette.textPrimary)
                Text(statusDetail)
                    .font(AppFont.bodySm)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if checkingStatus {
                ProgressView().controlSize(.small)
            } else {
                Button { Task { await refreshStatus() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh sync status")
            }
        }
        .padding(Metrics.spaceSm)
        .frame(maxWidth: .infinity)
        .background(statusColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        guard let status else { return Palette.textMuted }
        if !status.reachable { return Palette.textMuted }
        if status.localPending > 0 { return Palette.primary }
        if status.serverAhead { return Palette.warning }
        return Palette.success
    }

    private var statusIcon: String {
        guard let status, status.reachable else { return "icloud.slash" }
        if status.localPending > 0 { return "arrow.up.circle.fill" }
        if status.serverAhead { return "arrow.down.circle.fill" }
        return "checkmark.icloud.fill"
    }

    private var statusTitle: String {
        guard let status else { return checkingStatus ? "Checking…" : "Sync status" }
        if !status.reachable { return "Can't reach the server" }
        if status.localPending > 0 { return "\(status.localPending) review\(status.localPending == 1 ? "" : "s") to push" }
        if status.serverAhead { return "Cloud has new changes" }
        return "Up to date"
    }

    private var statusDetail: String {
        guard let status else { return "" }
        if !status.reachable { return "Showing local state only." }
        if status.localPending > 0 { return "Tap Sync Progress to push your reviews." }
        if status.serverAhead { return "Tap Sync Progress to pull the latest." }
        return "Local and cloud are in sync."
    }

    private func refreshStatus() async {
        guard auth.isLoggedIn, let creds = auth.credentials else { status = nil; return }
        checkingStatus = true
        defer { checkingStatus = false }
        status = await engine.checkStatus(in: modelContext, credentials: creds)
    }

    // MARK: Cloud actions (the two things v1 does)

    private var cloudActions: some View {
        VStack(spacing: Metrics.spaceXs) {
            Button(action: syncNow) {
                actionLabel(isSyncing ? "Synchronizing…" : "Sync Progress",
                            system: "arrow.triangle.2.circlepath",
                            spinning: isSyncing,
                            filled: true)
            }
            .disabled(isSyncing || isPulling)

            Button(action: pullDecks) {
                actionLabel(isPulling ? "Downloading decks…" : "Download Decks",
                            system: "icloud.and.arrow.down",
                            spinning: isPulling,
                            filled: false)
            }
            .disabled(isSyncing || isPulling)
        }
    }

    private func actionLabel(_ title: String, system: String, spinning: Bool, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: spinning)
            Text(title)
        }
        .font(AppFont.headlineSm)
        .foregroundStyle(filled ? Palette.canvas : Palette.primary)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.touchComfortable)
        .background(
            filled ? AnyShapeStyle(Palette.primary) : AnyShapeStyle(Palette.primary.opacity(0.15)),
            in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                .strokeBorder(filled ? .clear : Palette.primary.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: Storage

    private var storageCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Offline & Storage")
                .padding(.bottom, Metrics.spaceXs)

            VStack(spacing: 0) {
                toggleRow(
                    title: "Media Syncing",
                    subtitle: "Download referenced audio & images when you Download Decks.",
                    isOn: $mediaSyncing
                )
                Divider().overlay(Palette.hairline)
                cacheRow
            }
            .surfaceCard(padding: 0, cornerRadius: Metrics.radiusCard)
        }
        .task { refreshStorage() }
        .alert("Prune Media Cache", isPresented: $confirmPrune) {
            Button("Delete \(mediaFiles) file\(mediaFiles == 1 ? "" : "s")", role: .destructive) {
                MediaStore.clear(); refreshStorage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes downloaded audio/images (\(byteText(mediaBytes))). They'll re-download on the next Download Decks. Your decks and progress are untouched.")
        }
    }

    private func refreshStorage() {
        dbBytes = CollectionStore.sizeBytes
        mediaBytes = MediaStore.sizeBytes
        mediaFiles = MediaStore.fileCount
    }

    private func byteText(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: Metrics.spaceSm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppFont.labelMd).foregroundStyle(Palette.textPrimary)
                Text(subtitle).font(AppFont.bodySm).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Palette.success)
        }
        .padding(Metrics.spaceMd)
    }

    private var cacheRow: some View {
        let total = max(1, dbBytes + mediaBytes)
        return VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack {
                Text("On-Device Storage").font(AppFont.bodySm).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(byteText(dbBytes + mediaBytes)).font(AppFont.monoSm).foregroundStyle(Palette.primary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Palette.primary.frame(width: geo.size.width * CGFloat(dbBytes) / CGFloat(total))
                    Palette.success.frame(width: geo.size.width * CGFloat(mediaBytes) / CGFloat(total))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            .background(Palette.surfaceElevated)
            .clipShape(Capsule())
            HStack {
                legendDot(Palette.primary, "DB \(byteText(dbBytes))")
                legendDot(Palette.success, "Media \(byteText(mediaBytes)) · \(mediaFiles)")
                Spacer()
                Button("Prune Media") { confirmPrune = true }
                    .font(AppFont.labelSm)
                    .foregroundStyle(mediaFiles == 0 ? Palette.textMuted : Palette.primary)
                    .disabled(mediaFiles == 0)
            }
        }
        .padding(Metrics.spaceMd)
        .background(Palette.surfaceLow.opacity(0.7))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(AppFont.monoSm).foregroundStyle(Palette.textSecondary)
        }
        .padding(.trailing, Metrics.spaceSm)
    }

    // MARK: Activity

    private var activityCard: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Recent Activity")
                .padding(.bottom, Metrics.spaceXs)
            VStack(spacing: 0) {
                ForEach(Array(activity.enumerated()), id: \.element.id) { pair in
                    if pair.offset > 0 { Divider().overlay(Palette.hairline) }
                    activityRow(pair.element)
                }
            }
            .surfaceCard(padding: 0, cornerRadius: Metrics.radiusCard)
        }
    }

    private func activityRow(_ entry: ActivityEntry) -> some View {
        let isProgress = entry.kind == .progress
        let color = isProgress ? Palette.success : Palette.primary
        let icon = isProgress ? "checkmark.circle.fill" : "icloud.and.arrow.down"
        return HStack(alignment: .top, spacing: Metrics.spaceSm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(entry.title).font(AppFont.labelMd).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(entry.time).font(AppFont.monoSm).foregroundStyle(Palette.textMuted)
                }
                Text(entry.detail).font(AppFont.bodySm).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.spaceMd)
    }

    private var logoutButton: some View {
        Button { auth.logOut() } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Log Out")
            }
            .font(AppFont.labelMd)
            .foregroundStyle(Palette.critical)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.touchComfortable)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
                    .strokeBorder(Palette.critical.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.top, Metrics.spaceXs)
    }

    // MARK: Actions

    private func performLogin() {
        isLoggingIn = true
        loginError = nil
        Task {
            defer { isLoggingIn = false }
            do {
                try await auth.logIn(username: loginUser, password: loginPassword, host: loginHost)
                loginPassword = ""
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    private func syncNow() {
        guard let creds = auth.credentials else { return }
        isSyncing = true
        syncProgress = 0
        Task {
            defer { isSyncing = false }
            do {
                let summary = try await engine.syncProgress(in: modelContext, credentials: creds) { stage in
                    withAnimation { syncStageText = stage.text; syncProgress = stage.progress }
                }
                lastSync = "Just now"
                let entry = syncActivityEntry(pushed: summary.reviewsSynced, pulled: summary.reviewsPulled)
                activity.insert(entry, at: 0)
                await refreshStatus()
            } catch SyncError.fullSyncRequired(let reason) {
                conflict = ConflictPrompt(reason: reason)
            } catch {
                syncStageText = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    /// Force Upload: make this device's collection the cloud copy (conflict resolution).
    private func forceUpload() {
        guard let creds = auth.credentials else { return }
        isSyncing = true
        syncProgress = 0
        Task {
            defer { isSyncing = false }
            do {
                try await engine.forceUpload(in: modelContext, credentials: creds)
                lastSync = "Just now"
                activity.insert(
                    ActivityEntry(kind: .progress, title: "Uploaded to Cloud",
                                  detail: "This device's collection is now the cloud copy.", time: "now"),
                    at: 0
                )
                await refreshStatus()
            } catch {
                syncStageText = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    /// Builds a two-way sync activity row from how much was pushed up and pulled down.
    private func syncActivityEntry(pushed: Int, pulled: Int) -> ActivityEntry {
        if pushed == 0 && pulled == 0 {
            return ActivityEntry(kind: .progress, title: "Already Up to Date",
                                 detail: "No changes to sync.", time: "now")
        }
        var parts: [String] = []
        if pushed > 0 { parts.append("\(pushed) pushed") }
        if pulled > 0 { parts.append("\(pulled) pulled") }
        return ActivityEntry(kind: .progress, title: "Progress Synced",
                             detail: parts.joined(separator: " · "), time: "now")
    }

    /// Download Decks entry point: guard against discarding unpushed reviews before the
    /// full download-and-replace. Offers to Sync first.
    private func pullDecks() {
        let pending = CollectionStore.pendingReviewCount()
        if pending > 0 {
            pullGuard = PullGuardPrompt(pending: pending)
        } else {
            performPull()
        }
    }

    /// Runs Sync Progress, then continues with the download once local changes are safely pushed.
    private func syncThenPull() {
        guard let creds = auth.credentials else { return }
        isSyncing = true
        syncProgress = 0
        Task {
            do {
                _ = try await engine.syncProgress(in: modelContext, credentials: creds) { stage in
                    withAnimation { syncStageText = stage.text; syncProgress = stage.progress }
                }
                isSyncing = false
                performPull()
            } catch SyncError.fullSyncRequired(let reason) {
                isSyncing = false
                conflict = ConflictPrompt(reason: reason)
            } catch {
                isSyncing = false
                syncStageText = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    /// The actual full download-and-replace. Also used by Force Download (cloud wins),
    /// which is an explicit choice and so bypasses the pull guard.
    private func performPull() {
        guard let creds = auth.credentials else { return }
        isPulling = true
        syncProgress = 0
        Task {
            defer { isPulling = false }
            do {
                let result = try await engine.pullDecks(into: modelContext, credentials: creds) { stage in
                    withAnimation { syncStageText = stage.text; syncProgress = stage.progress }
                }
                let cardsText = result.newCards == 0
                    ? "no new cards"
                    : "\(result.newCards) new card\(result.newCards == 1 ? "" : "s")"
                activity.insert(
                    ActivityEntry(kind: .deck, title: "Deck Updated",
                                  detail: "\(result.deckName) · \(cardsText) · \(String(format: "%.1f", result.sizeMB)) MB",
                                  time: "now"),
                    at: 0
                )
                await refreshStatus()
                refreshStorage()
            } catch {
                activity.insert(
                    ActivityEntry(kind: .deck, title: "Pull failed",
                                  detail: error.localizedDescription, time: "now"),
                    at: 0
                )
            }
        }
    }
}

// MARK: - Conflict resolution sheet

/// Themed Force Upload / Download chooser shown when a normal sync can't reconcile.
private struct ConflictSheet: View {
    let reason: String
    let onDownload: () -> Void
    let onUpload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Metrics.spaceMd) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Palette.warning)
                .padding(.top, Metrics.spaceMd)

            VStack(spacing: Metrics.spaceXs) {
                Text("Sync Conflict")
                    .font(AppFont.headlineLg)
                    .foregroundStyle(Palette.textPrimary)
                Text(reason)
                    .font(AppFont.bodyMd)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Metrics.spaceXs) {
                choice(icon: "icloud.and.arrow.down", title: "Download from Cloud",
                       subtitle: "Replace this device's copy with the cloud's.",
                       color: Palette.primary, action: onDownload)
                choice(icon: "icloud.and.arrow.up", title: "Upload to Cloud",
                       subtitle: "Replace the cloud with this device's copy.",
                       color: Palette.warning, action: onUpload)
            }

            Button(action: onCancel) {
                Text("Cancel")
                    .font(AppFont.labelMd)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.touchComfortable)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.screenMargin)
        .padding(.bottom, Metrics.spaceSm)
        .frame(maxWidth: .infinity)
        .background(Palette.canvas)
    }

    private func choice(icon: String, title: String, subtitle: String,
                        color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.spaceSm) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.labelMd).foregroundStyle(Palette.textPrimary)
                    Text(subtitle).font(AppFont.bodySm).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textMuted)
            }
            .padding(Metrics.spaceSm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .strokeBorder(color.opacity(0.28), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SyncView()
        .modelContainer(sampleContainer())
        .environment(AuthController(engine: MockSyncEngine()))
        .preferredColorScheme(.dark)
}

#Preview("Conflict sheet") {
    ConflictSheet(
        reason: "The collection changed structurally on the server (schema mismatch). Choose which copy to keep.",
        onDownload: {}, onUpload: {}, onCancel: {}
    )
    .preferredColorScheme(.dark)
}
