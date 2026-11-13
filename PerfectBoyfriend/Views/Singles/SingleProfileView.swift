import PhotosUI
import SwiftUI
import UIKit

struct SingleProfileView: View {
    let profile: SingleProfile
    @ObservedObject var profileService: SingleProfileService
    @ObservedObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        Text("Profil")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)

                        identityCard

                        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                            PBSectionTitle(title: "Matching")
                            matchingCard
                            NavigationLink {
                                SingleProfileEditorView(profile: profile, profileService: profileService, suggestedName: profile.displayName)
                            } label: {
                                SingleProfileActionRow(
                                    symbol: "slider.horizontal.3",
                                    title: "Profil & Präferenzen",
                                    subtitle: "Interessen, Stimmung und Sichtbarkeit"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                            PBSectionTitle(title: "Vertrauen & Sicherheit")
                            NavigationLink {
                                SingleVerificationView(authManager: authManager)
                            } label: {
                                SingleProfileActionRow(
                                    symbol: "person.badge.shield.checkmark",
                                    title: "Identität bestätigen",
                                    subtitle: (authManager.appUser?.verificationStatus ?? .unverified).label
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                            PBSectionTitle(title: "Konto")
                            VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                                NavigationLink {
                                    PushNotificationSettingsView(authManager: authManager)
                                } label: {
                                    HStack {
                                        Label("Benachrichtigungen", systemImage: "bell")
                                            .font(PBTheme.Typography.body.weight(.semibold))
                                            .foregroundStyle(PBTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(PBTheme.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    AccountManagementView(authManager: authManager)
                                } label: {
                                    HStack {
                                        Label("Konto & Sicherheit", systemImage: "lock.shield")
                                            .font(PBTheme.Typography.body.weight(.semibold))
                                            .foregroundStyle(PBTheme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(PBTheme.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button("Abmelden", role: .destructive) {
                                    try? authManager.signOut()
                                }
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.destructive)
                            }
                            .padding(PBTheme.Spacing.md)
                            .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        }
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack(spacing: PBTheme.Spacing.md) {
                Group {
                    if let avatarPath = profile.avatarPath, !avatarPath.isEmpty {
                        StorageImageView(path: avatarPath)
                    } else {
                        Text(String(profile.displayName.prefix(1)).uppercased())
                            .font(.system(size: 25, weight: .medium))
                            .foregroundStyle(PBTheme.accent)
                    }
                }
                .frame(width: 66, height: 66)
                .background(PBTheme.accentMuted, in: Circle())
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                    Text(profile.displayName)
                        .font(PBTheme.Typography.title)
                        .foregroundStyle(PBTheme.textPrimary)
                    Text("\(profile.age) · \(profile.city)")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textSecondary)
                }
            }
            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textPrimary)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero, style: .continuous))
        .shadow(color: PBTheme.Shadow.card, radius: 12, y: 6)
    }

    private var matchingCard: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Text("Status")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textSecondary)
                Spacer()
                Text(profile.isMatchingActive ? "Aktiv" : "Pausiert")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(profile.isMatchingActive ? PBTheme.success : PBTheme.textSecondary)
            }
            HStack {
                Text("Altersspanne")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textSecondary)
                Spacer()
                Text("\(profile.preferredAgeMinimum)–\(profile.preferredAgeMaximum)")
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textPrimary)
            }
            if !profile.interests.isEmpty {
                Text(profile.interests.joined(separator: " · "))
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.accent)
                    .padding(.top, PBTheme.Spacing.xs)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }
}

private struct SingleProfileActionRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PBTheme.accent)
                .frame(width: 38, height: 38)
                .background(PBTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                Text(title)
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textPrimary)
                Text(subtitle)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }
}

struct SingleProfileEditorView: View {
    private static let suggestedInterests = ["Essen gehen", "Spazieren", "Museen", "Konzerte", "Sport", "Kino", "Kaffee", "Reisen"]

    let profile: SingleProfile?
    @ObservedObject var profileService: SingleProfileService
    let suggestedName: String

    @State private var draft: SingleProfileDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var avatarPreview: UIImage?
    @Environment(\.dismiss) private var dismiss

    init(profile: SingleProfile?, profileService: SingleProfileService, suggestedName: String) {
        self.profile = profile
        self.profileService = profileService
        self.suggestedName = suggestedName
        _draft = State(initialValue: profile.map(SingleProfileDraft.init) ?? SingleProfileDraft(suggestedName: suggestedName))
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text(profile == nil ? "Dein Profil" : "Profil bearbeiten")
                                .font(PBTheme.Typography.display)
                                .foregroundStyle(PBTheme.textOnDark)
                            Text(profile == nil ? "Ein paar Details genügen, damit deine Vorschläge persönlich bleiben." : "Mach dein Kennenlernprofil wieder ganz zu dir passend.")
                                .font(PBTheme.Typography.body)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        editorSection(title: "Dein Foto", caption: "Das Foto ist nur im aktivierten Kennenlern-Bereich sichtbar.") {
                            HStack(spacing: PBTheme.Spacing.md) {
                                avatarEditorPreview
                                VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                                    PhotosPicker(selection: $avatarItem, matching: .images) {
                                        Label(draft.avatarPath == nil && avatarPreview == nil ? "Foto auswählen" : "Foto ändern", systemImage: "photo")
                                            .font(PBTheme.Typography.caption.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(PBTheme.accent)
                                    if draft.avatarPath != nil || avatarPreview != nil {
                                        Button("Foto entfernen", role: .destructive) {
                                            avatarData = nil
                                            avatarPreview = nil
                                            avatarItem = nil
                                            draft.avatarPath = nil
                                            draft.removesAvatar = true
                                        }
                                        .font(PBTheme.Typography.caption.weight(.semibold))
                                    }
                                }
                            }
                        }

                        editorSection(title: "Über dich") {
                            VStack(spacing: PBTheme.Spacing.sm) {
                                TextField("Name", text: $draft.displayName)
                                    .singleEditorField()
                                TextField("Stadt", text: $draft.city)
                                    .singleEditorField()
                                Stepper("Alter: \(draft.age)", value: $draft.age, in: 18...99)
                                    .font(PBTheme.Typography.body.weight(.medium))
                                    .foregroundStyle(PBTheme.textPrimary)
                                    .tint(PBTheme.accent)
                                    .padding(.vertical, PBTheme.Spacing.xs)
                                TextField("Kurze Bio (optional)", text: $draft.bio, axis: .vertical)
                                    .lineLimit(2...4)
                                    .singleEditorField()
                            }
                        }

                        editorSection(title: "Wonach du suchst") {
                            VStack(spacing: PBTheme.Spacing.sm) {
                                Stepper("Mindestens: \(draft.preferredAgeMinimum)", value: $draft.preferredAgeMinimum, in: 18...99)
                                Stepper("Höchstens: \(draft.preferredAgeMaximum)", value: $draft.preferredAgeMaximum, in: 18...99)
                                Picker("Budget", selection: $draft.budgetPreference) {
                                    ForEach(BudgetLevel.allCases) { level in
                                        Text(level.label).tag(level)
                                    }
                                }
                            }
                            .font(PBTheme.Typography.body.weight(.medium))
                            .foregroundStyle(PBTheme.textPrimary)
                            .tint(PBTheme.accent)
                        }

                        editorSection(title: "Interessen", caption: "Bis zu acht Interessen") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: PBTheme.Spacing.sm)], alignment: .leading, spacing: PBTheme.Spacing.sm) {
                                ForEach(Self.suggestedInterests, id: \.self) { interest in
                                    PBFilterChip(
                                        title: interest,
                                        isSelected: draft.interests.contains(interest),
                                        action: { toggleInterest(interest) }
                                    )
                                }
                            }
                        }

                        editorSection(title: "Date-Stimmung", caption: "Wähle ein bis drei Stimmungen") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: PBTheme.Spacing.sm)], alignment: .leading, spacing: PBTheme.Spacing.sm) {
                                ForEach(Mood.options(for: .date)) { mood in
                                    PBFilterChip(
                                        title: mood.label,
                                        isSelected: draft.moods.contains(mood),
                                        action: { toggleMood(mood) }
                                    )
                                }
                            }
                        }

                        editorSection(title: "Sichtbarkeit") {
                            VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                                Toggle("Für Matching-Vorschläge sichtbar", isOn: $draft.isMatchingActive)
                                    .font(PBTheme.Typography.body.weight(.medium))
                                    .tint(PBTheme.accent)
                                Text("Deine E-Mail, Telefonnummer und dein genauer Standort werden nicht gezeigt.")
                                    .font(PBTheme.Typography.caption)
                                    .foregroundStyle(PBTheme.textSecondary)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.destructive)
                                .padding(PBTheme.Spacing.md)
                                .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        }

                        PBPrimaryButton(
                            title: profile == nil ? "Single-Profil erstellen" : "Änderungen speichern",
                            symbol: profile == nil ? "checkmark" : "checkmark.circle",
                            isLoading: isSaving,
                            action: { Task { await save() } }
                        )
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, PBTheme.Spacing.md)
                    .padding(.top, PBTheme.Spacing.md)
                    .padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                if profile != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { dismiss() }
                            .foregroundStyle(PBTheme.textOnDark)
                    }
                }
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task { await loadAvatar(item) }
            }
        }
    }

    private var isValid: Bool {
        !draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.preferredAgeMinimum <= draft.preferredAgeMaximum
            && !draft.moods.isEmpty
    }

    private func toggleInterest(_ interest: String) {
        if let index = draft.interests.firstIndex(of: interest) {
            draft.interests.remove(at: index)
        } else if draft.interests.count < 8 {
            draft.interests.append(interest)
        }
    }

    private func toggleMood(_ mood: Mood) {
        if let index = draft.moods.firstIndex(of: mood) {
            if draft.moods.count > 1 { draft.moods.remove(at: index) }
        } else if draft.moods.count < 3 {
            draft.moods.append(mood)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await profileService.save(draft, avatarData: avatarData)
            if profile != nil { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var avatarEditorPreview: some View {
        Group {
            if let avatarPreview {
                Image(uiImage: avatarPreview).resizable().scaledToFill()
            } else if let path = draft.avatarPath, !draft.removesAvatar {
                StorageImageView(path: path)
            } else {
                Text(String(draft.displayName.prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(PBTheme.textPrimary)
            }
        }
        .frame(width: 82, height: 82)
        .background(PBTheme.accentMuted, in: Circle())
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.accent.opacity(0.25), lineWidth: 1) }
    }

    private func loadAvatar(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw ImageUploadError.invalidImage
            }
            avatarData = data
            avatarPreview = image
            draft.removesAvatar = false
            errorMessage = nil
        } catch {
            avatarItem = nil
            avatarData = nil
            avatarPreview = nil
            errorMessage = "Das ausgewählte Foto konnte nicht geladen werden."
        }
    }

    private func editorSection<Content: View>(title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text(title)
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            content()
            if let caption {
                Text(caption)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }
}

private extension View {
    func singleEditorField() -> some View {
        self
            .font(PBTheme.Typography.body)
            .foregroundStyle(PBTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(PBTheme.surfaceMuted.opacity(0.65), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
    }
}
