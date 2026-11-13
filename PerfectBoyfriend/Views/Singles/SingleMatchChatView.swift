import SwiftUI

struct SingleMatchChatView: View {
    let match: SingleMatchPreview
    let ownProfile: SingleProfile
    @StateObject private var chatService = SingleMatchChatService()
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        PBScreenContainer {
            VStack(spacing: 0) {
                safetyNotice

                if chatService.messages.isEmpty {
                    PBEmptyState(
                        symbol: "bubble.left.and.bubble.right",
                        title: "Noch keine Nachrichten",
                        message: "Sag kurz Hallo – persönliche Kontaktangaben bleiben dabei privat."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: PBTheme.Spacing.sm) {
                                ForEach(chatService.messages) { message in
                                    ChatBubble(message: message, isOwn: message.senderUid == ownProfile.uid)
                                        .id(message.id)
                                }
                            }
                            .padding(PBTheme.Spacing.md)
                        }
                        .onChange(of: chatService.messages.last?.id) { _, lastID in
                            guard let lastID else { return }
                            withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                        }
                        .onAppear {
                            if let lastID = chatService.messages.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: PBTheme.Spacing.sm) {
                    TextField("Nachricht schreiben", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .font(PBTheme.Typography.body)
                        .foregroundStyle(PBTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(PBTheme.surfaceMuted.opacity(0.75), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                        .focused($isComposerFocused)

                    Button {
                        Task { await send() }
                    } label: {
                        if chatService.isSending {
                            ProgressView()
                                .tint(PBTheme.textPrimary)
                                .frame(width: 46, height: 46)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(PBTheme.textPrimary)
                                .frame(width: 46, height: 46)
                                .background(PBTheme.surface, in: Circle())
                        }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isSending)
                    .accessibilityLabel("Nachricht senden")
                }
                .padding(PBTheme.Spacing.md)
                .background(PBTheme.midnightRaised.opacity(0.94))
            }
        }
        .navigationTitle("Chat mit \(match.profile.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(PBTheme.midnight, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: match.matchId) {
            chatService.startListening(matchId: match.matchId)
            await chatService.markRead(matchId: match.matchId)
        }
        .onChange(of: chatService.messages.last?.id) { _, _ in
            Task { await chatService.markRead(matchId: match.matchId) }
        }
        .onDisappear {
            chatService.stopListening()
        }
        .alert("Nachricht nicht gesendet", isPresented: Binding(
            get: { chatService.errorMessage != nil },
            set: { if !$0 { chatService.errorMessage = nil } }
        )) {
            Button("OK") { chatService.errorMessage = nil }
        } message: {
            Text(chatService.errorMessage ?? "")
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: PBTheme.Spacing.xs) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(PBTheme.accent)
            Text("Bleibt zum Kennenlernen in der App: keine Telefonnummern, Links oder Live-Standorte teilen.")
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PBTheme.surface)
    }

    private func send() async {
        let sentDraft = draft
        guard await chatService.send(matchId: match.matchId, body: sentDraft) else { return }
        if draft == sentDraft { draft = "" }
        isComposerFocused = true
    }
}

private struct ChatBubble: View {
    let message: SingleChatMessage
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 48) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(isOwn ? PBTheme.textOnDark : PBTheme.textPrimary)
                    .padding(.horizontal, PBTheme.Spacing.sm)
                    .padding(.vertical, PBTheme.Spacing.xs)
                    .background(isOwn ? PBTheme.midnightRaised : PBTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
                Text(message.createdAt.dateValue(), format: .dateTime.hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(PBTheme.textSecondary)
            }
            if !isOwn { Spacer(minLength: 48) }
        }
    }
}
