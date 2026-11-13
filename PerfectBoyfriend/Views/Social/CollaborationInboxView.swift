import SwiftUI

struct CollaborationInboxView: View {
    let uid: String
    @StateObject private var service = CollaborationInboxService()
    @State private var respondingPostID: String?
    @State private var errorMessage: String?

    var body: some View {
        PBScreenContainer {
            Group {
                if service.isLoading {
                    ProgressView().tint(PBTheme.textOnDark)
                } else if service.invitations.isEmpty {
                    PBEmptyState(symbol: "person.2.badge.gearshape", title: "Keine offenen Einladungen",
                                 message: "Wenn dich jemand zu einem Moment einlädt, entscheidest du hier selbst darüber.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.md) {
                            Text("Gemeinsam veröffentlichen")
                                .font(PBTheme.Typography.display).foregroundStyle(PBTheme.textOnDark)
                            Text("Nur bestätigte Momente erscheinen auf deinem persönlichen Profil.")
                                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                            ForEach(service.invitations) { post in invitation(post) }
                        }
                        .padding(PBTheme.Spacing.md)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .navigationTitle("")
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { service.startListening(uid: uid) }
        .alert("Antwort konnte nicht gespeichert werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Unbekannter Fehler") }
    }

    private func invitation(_ post: SocialPost) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text("@\(post.creator?.handle ?? post.author.handle) möchte diesen Moment mit dir teilen")
                .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
            if !post.caption.isEmpty { Text(post.caption).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(3) }
            HStack(spacing: 10) {
                Button { Task { await respond(post, accept: false) } } label: {
                    Text("Ablehnen").frame(maxWidth: .infinity, minHeight: 42)
                        .background(.white.opacity(0.10), in: Capsule())
                }
                Button { Task { await respond(post, accept: true) } } label: {
                    Text("Bestätigen").frame(maxWidth: .infinity, minHeight: 42)
                        .background(PBTheme.surface, in: Capsule())
                }
            }
            .font(PBTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(PBTheme.textOnDark)
            .buttonStyle(.plain)
            .disabled(respondingPostID == post.id)
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    private func respond(_ post: SocialPost, accept: Bool) async {
        respondingPostID = post.id
        defer { respondingPostID = nil }
        do { try await service.respond(to: post, accept: accept) }
        catch { errorMessage = error.localizedDescription }
    }
}
