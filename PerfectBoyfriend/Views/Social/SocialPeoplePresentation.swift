import SwiftUI

/// A Moment belongs visually to everyone who chose to appear on it. `creator` remains a server
/// ownership detail, but it is intentionally not elevated in the community UI.
struct SocialPeoplePresentation: View {
    enum Style { case compact, expanded }

    let people: [SocialPersonIdentity]
    var style: Style = .compact

    private var uniquePeople: [SocialPersonIdentity] {
        var seen = Set<String>()
        return people.filter { seen.insert($0.uid).inserted }
    }

    var body: some View {
        switch style {
        case .compact: compact
        case .expanded: expanded
        }
    }

    private var compact: some View {
        HStack(spacing: PBTheme.Spacing.sm) {
            HStack(spacing: -10) {
                ForEach(uniquePeople.prefix(5)) { person in personOrb(person, size: 34) }
                if uniquePeople.count > 5 {
                    Text("+\(uniquePeople.count - 5)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(PBTheme.midnight)
                        .frame(width: 34, height: 34).background(PBTheme.surface, in: Circle())
                        .overlay { Circle().stroke(PBTheme.midnight.opacity(0.32), lineWidth: 2) }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(uniquePeople.count > 1 ? "Gemeinsam erlebt" : "Erlebt von")
                    .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                Text(uniquePeople.map { "@\($0.handle)" }.prefix(2).joined(separator: " · "))
                    .font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gemeinsam erlebt von \(uniquePeople.map(\.displayName).joined(separator: ", "))")
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            HStack {
                Text("Gemeinsam erlebt von")
                    .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                Spacer()
                Text("\(uniquePeople.count) \(uniquePeople.count == 1 ? "Person" : "Menschen")")
                    .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: PBTheme.Spacing.sm) {
                ForEach(uniquePeople) { person in
                    VStack(spacing: 6) {
                        personOrb(person, size: 52)
                        Text(person.displayName)
                            .font(PBTheme.Typography.micro.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                            .lineLimit(1)
                        Text("@\(person.handle)")
                            .font(.system(size: 10, weight: .regular)).foregroundStyle(PBTheme.textOnDarkSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(PBTheme.Spacing.md)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func personOrb(_ person: SocialPersonIdentity, size: CGFloat) -> some View {
        Group {
            if let avatarPath = person.avatarPath {
                StorageImageView(path: avatarPath)
            } else {
                Text(String(person.displayName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.36, weight: .medium)).foregroundStyle(PBTheme.textOnDark)
            }
        }
        .frame(width: size, height: size)
        .background(.white.opacity(0.14), in: Circle())
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.midnight.opacity(0.42), lineWidth: 2) }
    }
}
