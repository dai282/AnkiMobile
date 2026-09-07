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

struct SyncView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("fullOfflineMode") private var fullOfflineMode = true
    @AppStorage("mediaSyncing") private var mediaSyncing = true

    @State private var isSyncing = false
    @State private var isPulling = false
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

    /// The sync backend. Swapped for a real AnkiWeb engine in V2 without touching this view.
    private let engine: any SyncEngine = MockSyncEngine()
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

            if isSyncing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(syncStageText).font(AppFont.monoSm).foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Int(syncProgress * 100))%").font(AppFont.monoSm).foregroundStyle(Palette.textSecondary)
                    }
                    ProgressView(value: syncProgress)
                        .tint(Palette.success)
                }
            }
        }
        .surfaceCard(cornerRadius: Metrics.radiusCard)
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
                actionLabel(isPulling ? "Pulling decks…" : "Pull Decks from Cloud",
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
                    title: "Full Offline Mode",
                    subtitle: "Keep all decks and media cached locally for zero-latency studying.",
                    isOn: $fullOfflineMode
                )
                Divider().overlay(Palette.hairline)
                toggleRow(
                    title: "Media Syncing",
                    subtitle: "Enabled on Wi-Fi and cellular networks.",
                    isOn: $mediaSyncing
                )
                Divider().overlay(Palette.hairline)
                cacheRow
            }
            .surfaceCard(padding: 0, cornerRadius: Metrics.radiusCard)
        }
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
        VStack(alignment: .leading, spacing: Metrics.spaceSm) {
            HStack {
                Text("Cache Allocation").font(AppFont.bodySm).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("84.2 MB / 1.2 GB").font(AppFont.monoSm).foregroundStyle(Palette.primary)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Palette.primary.frame(width: geo.size.width * 0.07)
                    Palette.success.frame(width: geo.size.width * 0.18)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 6)
            .background(Palette.surfaceElevated)
            .clipShape(Capsule())
            HStack {
                legendDot(Palette.primary, "DB 8.2MB")
                legendDot(Palette.success, "Media 76MB")
                Spacer()
                Button("Prune Cache") {}
                    .font(AppFont.labelSm)
                    .foregroundStyle(Palette.primary)
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
        isSyncing = true
        syncProgress = 0
        Task {
            defer { isSyncing = false }
            do {
                let summary = try await engine.syncProgress(in: modelContext) { stage in
                    withAnimation { syncStageText = stage.text; syncProgress = stage.progress }
                }
                lastSync = "Just now"
                activity.insert(
                    ActivityEntry(kind: .progress, title: "Progress Synced",
                                  detail: "\(summary.reviewsSynced) reviews synced across \(summary.decksTouched) decks · \(String(format: "%.1f", summary.duration))s",
                                  time: "now"),
                    at: 0
                )
            } catch {
                syncStageText = "Sync failed: \(error.localizedDescription)"
            }
        }
    }

    private func pullDecks() {
        isPulling = true
        Task {
            defer { isPulling = false }
            do {
                let result = try await engine.pullDecks(into: modelContext)
                activity.insert(
                    ActivityEntry(kind: .deck, title: "Deck Updated",
                                  detail: "\(result.deckName) · \(result.newCards) new cards pulled from AnkiWeb · \(String(format: "%.1f", result.sizeMB)) MB",
                                  time: "now"),
                    at: 0
                )
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

#Preview {
    SyncView()
        .modelContainer(sampleContainer())
        .environment(AuthController(engine: MockSyncEngine()))
        .preferredColorScheme(.dark)
}
