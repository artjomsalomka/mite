import SwiftUI

/// Private shared space for one confirmed match. No contact data, live position or direct
/// messaging is exposed here; the first available action is deliberately a public-place date
/// plan, whose server prompt applies the first-meeting safety rules.
struct SingleMatchDetailView: View {
    let match: SingleMatchPreview
    let ownProfile: SingleProfile
    @ObservedObject var matchingService: SingleMatchingService
    var opensChatInitially = false
    @StateObject private var savedDateService = SavedDateService()
    @StateObject private var postService = PostService()
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingBlockConfirmation = false
    @State private var isShowingReportOptions = false
    @State private var didReport = false
    @State private var safetyError: String?
    @State private var isChatPresented = false
    @State private var didApplyInitialDestination = false

    private var scope: DatePlanningScope { .singleMatch(id: match.matchId) }

    private var upcoming: [SavedDate] {
        savedDateService.savedDates
            .filter { $0.status == .upcoming && !$0.isInPast }
            .sorted { $0.scheduledAt.dateValue() < $1.scheduledAt.dateValue() }
    }

    private var past: [SavedDate] {
        savedDateService.savedDates
            .filter { $0.status == .completed || ($0.status == .upcoming && $0.isInPast) }
            .sorted { $0.scheduledAt.dateValue() > $1.scheduledAt.dateValue() }
    }

    private var cancelled: [SavedDate] {
        savedDateService.savedDates
            .filter { $0.status == .cancelled }
            .sorted { $0.scheduledAt.dateValue() > $1.scheduledAt.dateValue() }
    }

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    matchHeader
                    safetyCard

                    VStack(spacing: PBTheme.Spacing.sm) {
                        NavigationLink {
                            CriteriaFormView(match: match, ownProfile: ownProfile, savedDateService: savedDateService)
                        } label: {
                            PBOptionCard(
                                symbol: "sparkles",
                                title: "Erstes Date planen",
                                subtitle: "Ideen für einen öffentlichen, gut besuchten Ort"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SingleMatchChatView(match: match, ownProfile: ownProfile)
                        } label: {
                            PBOptionCard(
                                symbol: "bubble.left.and.bubble.right",
                                title: "In der App schreiben",
                                subtitle: "Kontaktangaben bleiben dabei privat"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    planningContent
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingReportOptions = true
                    } label: {
                        Label("Profil melden", systemImage: "exclamationmark.bubble")
                    }
                    Button(role: .destructive) {
                        isShowingBlockConfirmation = true
                    } label: {
                        Label("Profil blockieren", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Sicherheitsoptionen")
            }
        }
        .task(id: match.matchId) {
            savedDateService.startListening(scope: scope)
            guard opensChatInitially, !didApplyInitialDestination else { return }
            didApplyInitialDestination = true
            isChatPresented = true
        }
        .navigationDestination(isPresented: $isChatPresented) {
            SingleMatchChatView(match: match, ownProfile: ownProfile)
        }
        .confirmationDialog("Was möchtest du melden?", isPresented: $isShowingReportOptions, titleVisibility: .visible) {
            Button("Unangemessene Inhalte") { report(reason: "inappropriate") }
            Button("Sicherheitsbedenken") { report(reason: "safety") }
            Button("Spam") { report(reason: "spam") }
        }
        .alert("Profil blockieren?", isPresented: $isShowingBlockConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Blockieren", role: .destructive) {
                Task { await blockMatch() }
            }
        } message: {
            Text("Das Match und die gemeinsamen Date-Pläne werden für dich ausgeblendet.")
        }
        .alert("Meldung gesendet", isPresented: $didReport) {
            Button("OK") {}
        } message: {
            Text("Danke. Das Profil wurde zur Prüfung markiert.")
        }
        .alert("Aktion nicht möglich", isPresented: Binding(
            get: { safetyError != nil },
            set: { if !$0 { safetyError = nil } }
        )) {
            Button("OK") { safetyError = nil }
        } message: {
            Text(safetyError ?? "")
        }
    }

    private var matchHeader: some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.md) {
            Group {
                if let avatarPath = match.profile.avatarPath, !avatarPath.isEmpty {
                    StorageImageView(path: avatarPath)
                } else {
                    Text(String(match.profile.displayName.prefix(1)).uppercased())
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(PBTheme.accent)
                }
            }
            .frame(width: 68, height: 68)
            .background(PBTheme.accentMuted, in: Circle())
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                Text("Du & \(match.profile.displayName)")
                    .font(PBTheme.Typography.title)
                    .foregroundStyle(PBTheme.textOnDark)
                Text("\(match.profile.city) · \(match.profile.interests.prefix(3).joined(separator: " · "))")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                if match.profile.isVerified {
                    Label("Identität bestätigt", systemImage: "checkmark.seal.fill")
                        .font(PBTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(PBTheme.success)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Label("Sicher starten", systemImage: "shield.lefthalf.filled")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textPrimary)
            Text("Erste Ideen führen zu öffentlichen, gut besuchten Orten. Telefonnummer und genauer Standort bleiben privat.")
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var planningContent: some View {
        if savedDateService.isLoading && savedDateService.savedDates.isEmpty {
            ProgressView()
                .tint(PBTheme.textOnDark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PBTheme.Spacing.xl)
        } else if let loadErrorMessage = savedDateService.loadErrorMessage, savedDateService.savedDates.isEmpty {
            PBEmptyState(
                symbol: "wifi.exclamationmark",
                title: "Date-Ideen nicht erreichbar",
                message: loadErrorMessage,
                actionTitle: "Erneut versuchen",
                action: savedDateService.retryLoading
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, PBTheme.Spacing.xl)
        } else if upcoming.isEmpty && past.isEmpty && cancelled.isEmpty {
            PBEmptyState(
                symbol: "calendar.badge.plus",
                title: "Eure erste Idee",
                message: "Plant gemeinsam ein Date, wenn es sich für euch richtig anfühlt."
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, PBTheme.Spacing.xl)
        } else {
            if !upcoming.isEmpty {
                dateSection(title: "Geplant", dates: upcoming)
            }
            if !past.isEmpty {
                dateSection(title: "Vergangen", dates: past)
            }
            if !cancelled.isEmpty {
                dateSection(title: "Abgesagt", dates: cancelled)
            }
        }
    }

    private func dateSection(title: String, dates: [SavedDate]) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            PBSectionTitle(title: title)
            ForEach(dates) { savedDate in
                NavigationLink {
                    SavedDateDetailView(
                        scope: scope,
                        savedDate: savedDate,
                        savedDateService: savedDateService,
                        postService: postService
                    )
                } label: {
                    SingleMatchDateRow(savedDate: savedDate)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func report(reason: String) {
        Task {
            if await matchingService.report(match.profile, reason: reason) {
                didReport = true
            } else {
                safetyError = matchingService.actionError ?? "Die Meldung konnte nicht gesendet werden."
            }
        }
    }

    private func blockMatch() async {
        if await matchingService.block(match.profile) {
            dismiss()
        } else {
            safetyError = matchingService.actionError ?? "Das Profil konnte nicht blockiert werden."
        }
    }
}

private struct SingleMatchDateRow: View {
    let savedDate: SavedDate

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            Image(systemName: "calendar")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PBTheme.accent)
                .frame(width: 40, height: 40)
                .background(PBTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                Text(savedDate.title)
                    .font(PBTheme.Typography.body.bold())
                    .foregroundStyle(PBTheme.textPrimary)
                Text(savedDate.scheduledAt.dateValue(), format: .dateTime.day().month().year().hour().minute())
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textSecondary)
            }
            Spacer()
            statusBadge
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var statusBadge: some View {
        Group {
            if savedDate.status == .cancelled {
                Text("Abgesagt")
                    .foregroundStyle(PBTheme.destructive)
            } else if let rating = savedDate.rating {
                Label("\(rating.stars)", systemImage: "star.fill")
                    .foregroundStyle(PBTheme.warning)
            } else if savedDate.isInPast {
                Text("Bewerten")
                    .foregroundStyle(PBTheme.accent)
            } else {
                Text("Geplant")
                    .foregroundStyle(PBTheme.accent)
            }
        }
        .font(PBTheme.Typography.micro.weight(.semibold))
        .lineLimit(1)
    }
}
