import SwiftUI

/// The permanent Midnight Ink canvas. A restrained radial highlight recreates the depth of the
/// approved visual direction without relying on a raster background image.
struct PBMidnightBackground: View {
    var body: some View {
        ZStack {
            PBTheme.midnight
            RadialGradient(
                colors: [PBTheme.midnightSoft.opacity(0.72), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct PBScreenContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            PBMidnightBackground()
            content
        }
    }
}

struct PBGlassDock<Selection: Hashable>: View {
    struct Item: Identifiable {
        let id: String
        let selection: Selection
        let title: String
        let symbol: String
    }

    let items: [Item]
    @Binding var selection: Selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.34, extraBounce: 0.05)) {
                        selection = item.selection
                    }
                } label: {
                    VStack(spacing: PBTheme.Spacing.xs) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 18, weight: selection == item.selection ? .semibold : .regular))
                        Text(item.title)
                            .font(PBTheme.Typography.micro)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == item.selection ? PBTheme.textOnDark : PBTheme.textOnDarkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(selection == item.selection ? PBTheme.controlSelected : .clear, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.selection ? .isSelected : [])
            }
        }
        .padding(.horizontal, PBTheme.Spacing.sm)
        .background(PBTheme.controlSurfaceRaised.opacity(0.98), in: Capsule())
        .overlay {
            Capsule().stroke(PBTheme.controlBorder, lineWidth: 1)
        }
        .shadow(color: PBTheme.Shadow.dock, radius: 18, y: 8)
        .padding(.horizontal, PBTheme.Spacing.lg)
    }
}

struct PBSectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(PBTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }
}

struct PBFilterChip: View {
    let title: String
    let symbol: String?
    let isSelected: Bool
    let action: () -> Void

    init(title: String, symbol: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(PBTheme.Typography.caption.weight(.medium))
            .foregroundStyle(isSelected ? PBTheme.textOnDark : PBTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? PBTheme.accent : PBTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PBPlanButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 44, height: 44)
                .background(PBTheme.accent, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date planen")
        .accessibilityHint("Öffnet die gemeinsame Date-Planung")
    }
}

/// The one strong action per screen: a tonal Midnight surface with a controlled blue emphasis.
struct PBPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(PBTheme.textOnDark)
                } else if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(PBTheme.Typography.body.weight(.semibold))
            .foregroundStyle(PBTheme.textOnDark)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(PBTheme.controlSelected, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

/// A tappable-looking content card for one-out-of-several onboarding decisions. The parent owns
/// the actual Button or NavigationLink so the card stays usable in either interaction context.
struct PBOptionCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: PBTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(PBTheme.accent)
                .frame(width: 44, height: 44)
                .background(PBTheme.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: PBTheme.Spacing.xxs) {
                Text(title)
                    .font(PBTheme.Typography.headline)
                    .foregroundStyle(PBTheme.textPrimary)
                Text(subtitle)
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PBTheme.textSecondary)
        }
        .padding(PBTheme.Spacing.md)
        .background(PBTheme.surface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .shadow(color: PBTheme.Shadow.card, radius: 10, y: 5)
    }
}

struct PBIconCircleButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.16), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The small overlapping portraits make a shared plan feel personal without turning the home
/// header into a conventional account switcher. Member images are optional; initials retain the
/// same composed look until a person adds a photo to their profile.
struct PBMemberAvatarStack: View {
    let members: [CoupleMember]
    var avatarSize: CGFloat = 34
    var maxAvatars = 2

    var body: some View {
        HStack(spacing: -avatarSize * 0.28) {
            ForEach(Array(members.prefix(maxAvatars).enumerated()), id: \.element.uid) { index, member in
                PBMemberAvatar(member: member, index: index, size: avatarSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memberNames)
    }

    private var memberNames: String {
        let names = members.prefix(maxAvatars).map(\.displayName).joined(separator: " und ")
        return names.isEmpty ? "Euer Profil" : names
    }
}

struct PBMemberAvatar: View {
    let member: CoupleMember
    let index: Int
    let size: CGFloat

    var body: some View {
        Group {
            if let path = member.avatarPath, !path.isEmpty {
                StorageImageView(path: path)
            } else {
                Text(initials)
                    .font(.system(size: max(11, size * 0.32), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(avatarColor)
            }
        }
        .frame(width: size, height: size)
        .background(avatarColor)
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.surfaceOnDark, lineWidth: 2) }
    }

    private var initials: String {
        let parts = member.displayName.split(separator: " ")
        let characters = parts.prefix(2).compactMap(\.first)
        return characters.isEmpty ? "?" : String(characters).uppercased()
    }

    private var avatarColor: Color {
        switch index % 3 {
        case 0: return Color(red: 0.36, green: 0.56, blue: 0.78)
        case 1: return Color(red: 0.50, green: 0.40, blue: 0.67)
        default: return Color(red: 0.23, green: 0.56, blue: 0.52)
        }
    }
}

struct PBNotificationButton: View {
    let action: () -> Void
    var unreadCount: Int = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: "bell")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Circle()
                            .fill(PBTheme.accent)
                            .frame(width: 7, height: 7)
                            .overlay { Circle().stroke(PBTheme.midnight, lineWidth: 2) }
                            .offset(x: -2, y: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(unreadCount > 0 ? "Aktivität, \(unreadCount) offen" : "Aktivität")
        .accessibilityHint("Öffnet Einladungen und gemeinsame Beiträge")
    }
}

struct PBEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: PBTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
            Text(title)
                .font(PBTheme.Typography.title)
                .foregroundStyle(PBTheme.textOnDark)
            Text(message)
                .font(PBTheme.Typography.body)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(PBTheme.surface)
                    .foregroundStyle(PBTheme.textPrimary)
            }
        }
        .padding(PBTheme.Spacing.xl)
    }
}
