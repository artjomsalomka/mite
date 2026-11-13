import SwiftUI

struct CollaboratorPickerView: View {
    let excluding: String
    @Binding var selected: [PersonProfile]
    let title: String
    let selectionLimit: Int
    let excludingUIDs: Set<String>
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = PersonDirectoryStore()
    @State private var query = ""

    init(excluding: String, selected: Binding<[PersonProfile]>, title: String = "Mitwirkende", selectionLimit: Int = 5, excludingUIDs: Set<String> = []) {
        self.excluding = excluding
        _selected = selected
        self.title = title
        self.selectionLimit = selectionLimit
        self.excludingUIDs = excludingUIDs
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                Group {
                    if store.isLoading && store.profiles.isEmpty {
                        ProgressView().tint(PBTheme.textOnDark)
                    } else {
                        List(store.profiles.filter { !excludingUIDs.contains($0.uid) }) { profile in
                            Button { toggle(profile) } label: {
                                HStack(spacing: 12) {
                                    avatar(for: profile)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.displayName).foregroundStyle(PBTheme.textOnDark)
                                        Text("@\(profile.handle)").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(where: { $0.uid == profile.uid }) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(PBTheme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.foregroundStyle(PBTheme.textOnDark) }
            }
            .toolbarBackground(PBTheme.midnight, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $query, prompt: "Name oder @Handle")
            .onChange(of: query) { _, value in store.search(value, excluding: excluding) }
            .task { store.search("", excluding: excluding, immediate: true) }
        }
    }

    @ViewBuilder
    private func avatar(for profile: PersonProfile) -> some View {
        ZStack {
            Text(String(profile.displayName.prefix(1)).uppercased())
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.10))

            if let avatarPath = profile.avatarPath, !avatarPath.isEmpty {
                StorageImageView(path: avatarPath)
                    .id("\(profile.uid):\(avatarPath)")
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
    }

    private func toggle(_ profile: PersonProfile) {
        if let index = selected.firstIndex(where: { $0.uid == profile.uid }) {
            selected.remove(at: index)
        } else if selected.count < selectionLimit {
            selected.append(profile)
        }
    }
}
