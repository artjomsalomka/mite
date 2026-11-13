import PhotosUI
import SwiftUI
import UIKit

/// Explicit opt-in surface for a person's community identity. This is distinct from the private
/// account name/photo editor and makes the pair link visible without making it the account.
struct PublicIdentityEditorView: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var personProfileService: PersonProfileService

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var handle = ""
    @State private var bio = ""
    @State private var city = ""
    @State private var isDiscoverable = false
    @State private var avatarPath: String?
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        PBScreenContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                        Text("Dein öffentliches Profil")
                            .font(PBTheme.Typography.display)
                            .foregroundStyle(PBTheme.textOnDark)
                        Text("Du bleibst eine eigene Person. Deine Paarverbindung erscheint nur als dezente Kennzeichnung.")
                            .font(PBTheme.Typography.body)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                    }

                    VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                        field("Name", text: $displayName, placeholder: "Wie sollen andere dich sehen?")
                        field("Handle", text: $handle, placeholder: "dein_handle", prefix: "@")
                        field("Kurz über dich", text: $bio, placeholder: "Was macht dir gemeinsam Spaß?", axis: .vertical)
                        field("Stadt", text: $city, placeholder: "z. B. Marburg")
                    }
                    .padding(PBTheme.Spacing.md)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))

                    communityAvatarPicker

                    Toggle(isOn: $isDiscoverable) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("In der Profilsuche zeigen")
                                .font(PBTheme.Typography.body.weight(.semibold))
                            Text("Du kannst diese Einstellung jederzeit wieder ausschalten.")
                                .font(PBTheme.Typography.caption)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                    }
                    .tint(PBTheme.accent)
                    .padding(PBTheme.Spacing.md)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))

                    if authManager.appUser?.coupleId != nil {
                        Label("Als Paar verbunden", systemImage: "heart.link")
                            .font(PBTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(PBTheme.textOnDark)
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .background(.white.opacity(0.10), in: Capsule())
                    }

                    PBPrimaryButton(title: "Profil speichern", symbol: "checkmark", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || handle.count < 3)

                    if let errorMessage {
                        Text(errorMessage).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDark)
                            .padding(PBTheme.Spacing.sm).background(PBTheme.destructive, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    }
                }
                .padding(.horizontal, PBTheme.Spacing.md)
                .padding(.top, PBTheme.Spacing.md)
                .padding(.bottom, PBTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: hydrate)
        .onChange(of: personProfileService.profile) { _, _ in hydrate() }
        .onChange(of: pickedAvatar) { _, item in
            guard let item else { return }
            Task { avatarData = try? await item.loadTransferable(type: Data.self) }
        }
    }

    @ViewBuilder
    private func field(_ title: String, text: Binding<String>, placeholder: String, prefix: String? = nil,
                       axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(PBTheme.Typography.caption.weight(.medium)).foregroundStyle(PBTheme.textOnDarkSecondary)
            HStack(alignment: axis == .horizontal ? .center : .top, spacing: 0) {
                if let prefix { Text(prefix).foregroundStyle(PBTheme.textOnDarkSecondary).padding(.leading, PBTheme.Spacing.md) }
                TextField(placeholder, text: text, axis: axis)
                    .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                    .lineLimit(axis == .horizontal ? 1...1 : 2...4)
                    .padding(PBTheme.Spacing.md)
            }
            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
        }
    }

    private func hydrate() {
        guard let profile = personProfileService.profile else {
            if displayName.isEmpty { displayName = authManager.appUser?.displayName ?? "" }
            return
        }
        displayName = profile.displayName
        handle = profile.handle
        bio = profile.bio
        city = profile.city
        isDiscoverable = profile.isDiscoverable
        avatarPath = profile.avatarPath
    }

    private var communityAvatarPicker: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            PhotosPicker(selection: $pickedAvatar, matching: .images) {
                Group {
                    if let avatarData, let image = UIImage(data: avatarData) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if let avatarPath, !avatarPath.isEmpty {
                        StorageImageView(path: avatarPath)
                    } else {
                        Text(String(displayName.prefix(1)).uppercased())
                            .font(.system(size: 24, weight: .medium)).foregroundStyle(PBTheme.midnight)
                    }
                }
                .frame(width: 72, height: 72).background(PBTheme.surface, in: Circle()).clipShape(Circle())
                .overlay { Circle().stroke(.white.opacity(0.55), lineWidth: 1) }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(PBTheme.textOnDark)
                        .frame(width: 25, height: 25).background(PBTheme.accent, in: Circle())
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text("Community-Profilbild").font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                Text("Freiwillig. Dieses Bild ist nur sichtbar, wenn du dich in der Profilsuche zeigst – dein privates Profilfoto bleibt getrennt.")
                    .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var savedAvatarPath = avatarPath
            if let avatarData, let uid = authManager.firebaseUser?.uid {
                savedAvatarPath = try await ImageUploadService.uploadPublicAvatar(avatarData, uid: uid)
            }
            try await personProfileService.save(displayName: displayName, handle: handle, bio: bio, city: city,
                                                isDiscoverable: isDiscoverable, avatarPath: savedAvatarPath)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
