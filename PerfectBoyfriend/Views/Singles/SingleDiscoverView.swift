import SwiftUI

struct SingleDiscoverView: View {
    let profile: SingleProfile
    @ObservedObject var matchingService: SingleMatchingService
    @State private var profilePendingBlock: SingleSuggestion?

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text("Entdecken")
                                .font(PBTheme.Typography.display)
                                .foregroundStyle(PBTheme.textOnDark)
                            Text("Menschen, mit denen sich eine Date-Idee gut anfühlen könnte.")
                                .font(PBTheme.Typography.body)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        Text(profile.isMatchingActive
                             ? "Vorschläge richten sich nach Stadt, Altersspanne und euren gemeinsamen Interessen."
                             : "Dein Profil ist pausiert. Aktiviere Matching im Profil, um neue Vorschläge zu sehen.")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.textPrimary)
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))

                        content
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
                .refreshable { await matchingService.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Match!", isPresented: Binding(
                get: { matchingService.newMatch != nil },
                set: { if !$0 { matchingService.newMatch = nil } }
            )) {
                Button("Super", role: .cancel) {}
            } message: {
                Text("Du und \(matchingService.newMatch?.displayName ?? "dein Match") habt gegenseitiges Interesse. Ihr könnt jetzt in Ruhe ein erstes Date planen.")
            }
            .alert(
                "Profil blockieren?",
                isPresented: Binding(
                    get: { profilePendingBlock != nil },
                    set: { if !$0 { profilePendingBlock = nil } }
                ),
                presenting: profilePendingBlock
            ) { suggestion in
                Button("Blockieren", role: .destructive) {
                    Task { await matchingService.block(suggestion) }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: { suggestion in
                Text("\(suggestion.displayName) wird nicht mehr vorgeschlagen. Bestehende Interessen und Matches werden entfernt.")
            }
            .alert("Aktion nicht möglich", isPresented: Binding(
                get: { matchingService.actionError != nil },
                set: { if !$0 { matchingService.actionError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(matchingService.actionError ?? "Unbekannter Fehler")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if matchingService.isLoading && matchingService.suggestions.isEmpty {
            HStack {
                Spacer()
                ProgressView("Suche passende Ideen …")
                    .tint(PBTheme.textOnDark)
                    .foregroundStyle(PBTheme.textOnDark)
                Spacer()
            }
            .padding(.vertical, PBTheme.Spacing.xl)
        } else if matchingService.suggestions.isEmpty {
            PBEmptyState(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Noch keine passenden Vorschläge",
                message: "Passe Interessen oder Altersspanne an und schau später erneut vorbei."
            )
            .frame(maxWidth: .infinity)
            .padding(.top, PBTheme.Spacing.xl)
        } else {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                PBSectionTitle(title: "Mögliche Date-Begleitungen")
                ForEach(matchingService.suggestions) { suggestion in
                    SingleSuggestionCard(
                        suggestion: suggestion,
                        isPending: matchingService.pendingUids.contains(suggestion.uid),
                        onInterest: { Task { await matchingService.expressInterest(in: suggestion) } },
                        onReport: { Task { await matchingService.report(suggestion, reason: "inappropriate") } },
                        onBlock: { profilePendingBlock = suggestion }
                    )
                }
            }
        }
    }
}

private struct SingleSuggestionCard: View {
    let suggestion: SingleSuggestion
    let isPending: Bool
    let onInterest: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Group {
                    if let avatarPath = suggestion.avatarPath, !avatarPath.isEmpty {
                        StorageImageView(path: avatarPath)
                    } else {
                        Text(String(suggestion.displayName.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(PBTheme.accent)
                    }
                }
                .frame(width: 58, height: 58)
                .background(PBTheme.accentMuted, in: Circle())
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(suggestion.displayName), \(suggestion.age)")
                        .font(PBTheme.Typography.headline)
                        .foregroundStyle(PBTheme.textPrimary)
                    if suggestion.isVerified {
                        Label("Identität bestätigt", systemImage: "checkmark.seal.fill")
                            .font(PBTheme.Typography.caption)
                            .foregroundStyle(PBTheme.success)
                    }
                    Label(suggestion.city, systemImage: "mappin.and.ellipse")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textSecondary)
                }
                Spacer()
                Menu {
                    Button("Melden", action: onReport)
                    Button("Blockieren", role: .destructive, action: onBlock)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(PBTheme.textSecondary)
                }
            }

            if !suggestion.bio.isEmpty {
                Text(suggestion.bio)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textPrimary)
            }
            if !suggestion.interests.isEmpty {
                Text(suggestion.interests.joined(separator: " · "))
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.accent)
            }
            if suggestion.commonInterestCount > 0 {
                Label("\(suggestion.commonInterestCount) gemeinsame Interessen", systemImage: "sparkles")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textSecondary)
            }

            Button(action: onInterest) {
                if isPending {
                    ProgressView().tint(PBTheme.textOnDark).frame(maxWidth: .infinity)
                } else {
                    Label("Interesse zeigen", systemImage: "hand.thumbsup.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(PBTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(PBTheme.textOnDark)
            .padding(.vertical, 12)
            .background(PBTheme.accent, in: Capsule())
            .buttonStyle(.plain)
            .disabled(isPending)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .shadow(color: PBTheme.Shadow.card, radius: 10, y: 5)
    }
}
