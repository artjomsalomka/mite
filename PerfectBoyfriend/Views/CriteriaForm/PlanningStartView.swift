import SwiftUI

/// One entry point for every shared plan. The people are chosen before preferences because a
/// dinner for two and a table for six are fundamentally different recommendation problems.
struct PlanningStartView: View {
    let couple: Couple?
    let scope: DatePlanningScope
    let viewerUID: String
    let profileCity: String
    let savedDateService: SavedDateService
    var initialMode: PlanningMode = .date
    let onPlanSaved: (PlanningMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlanningMode
    @State private var invitees: [PersonProfile] = []
    @State private var isPeoplePickerPresented = false
    @State private var isCriteriaPresented = false

    init(couple: Couple, viewerUID: String, profileCity: String, savedDateService: SavedDateService, initialMode: PlanningMode = .date, onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }) {
        self.couple = couple
        self.scope = .couple(id: couple.id ?? "")
        self.viewerUID = viewerUID
        self.profileCity = profileCity
        self.savedDateService = savedDateService
        self.initialMode = initialMode
        self.onPlanSaved = onPlanSaved
        _mode = State(initialValue: initialMode)
    }

    init(personalUID: String, profileCity: String, savedDateService: SavedDateService, onPlanSaved: @escaping (PlanningMode) -> Void = { _ in }) {
        self.couple = nil
        self.scope = .personal(id: personalUID)
        self.viewerUID = personalUID
        self.profileCity = profileCity
        self.savedDateService = savedDateService
        self.initialMode = .group
        self.onPlanSaved = onPlanSaved
        _mode = State(initialValue: .group)
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: PBTheme.Spacing.xs) {
                            Text("Was plant ihr?")
                                .font(PBTheme.Typography.display).foregroundStyle(PBTheme.textOnDark)
                            Text("Erst die Menschen, dann die Idee. So passt der Vorschlag wirklich zu eurem Plan.")
                                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                        }

                        VStack(spacing: PBTheme.Spacing.sm) {
                            if couple != nil {
                                modeCard(
                                    mode: .date,
                                    title: "Date zu zweit",
                                    detail: "Ein gemeinsamer Abend für euch beide.",
                                    symbol: "sparkles"
                                )
                            }
                            modeCard(
                                mode: .group,
                                title: "Treffen mit Freund:innen",
                                detail: "Eine Idee, die für eure ganze Runde funktioniert.",
                                symbol: "person.3.fill"
                            )
                        }

                        if mode == .date, let couple {
                            audienceSurface(title: "Dabei") {
                                HStack(spacing: PBTheme.Spacing.sm) {
                                    PBMemberAvatarStack(members: couple.members, avatarSize: 40)
                                    Text("Ihr zwei")
                                        .font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
                                    Spacer()
                                    Text("2 Personen")
                                        .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                                }
                            }
                        } else {
                            audienceSurface(title: "Wer ist dabei?") {
                                VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
                                    HStack(spacing: PBTheme.Spacing.sm) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(PBTheme.midnight)
                                            .frame(width: 40, height: 40).background(PBTheme.surface, in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Du")
                                                .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                                            Text("Organisierst den Plan")
                                                .font(PBTheme.Typography.micro).foregroundStyle(PBTheme.textOnDarkSecondary)
                                        }
                                        Spacer()
                                        Text("+\(invitees.count)")
                                            .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.accent)
                                    }

                                    if invitees.isEmpty {
                                        Text("Wähle mindestens eine Person aus. Der KI-Vorschlag berücksichtigt danach die Größe eurer Runde.")
                                            .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                                    } else {
                                        ScrollView(.horizontal) {
                                            HStack(spacing: 8) {
                                                ForEach(invitees) { person in
                                                    selectedPerson(person)
                                                }
                                            }
                                        }
                                        .scrollIndicators(.hidden)
                                    }

                                    Button { isPeoplePickerPresented = true } label: {
                                        Label(invitees.isEmpty ? "Menschen auswählen" : "Menschen bearbeiten", systemImage: "person.badge.plus")
                                            .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.midnight)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(PBTheme.surface, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        PBPrimaryButton(
                            title: mode == .date ? "Date-Ideen einstellen" : "Ideen für die Gruppe einstellen",
                            symbol: "arrow.right",
                            isLoading: false
                        ) {
                            isCriteriaPresented = true
                        }
                        .disabled(mode == .group && invitees.isEmpty)
                    }
                    .padding(PBTheme.Spacing.md).padding(.bottom, PBTheme.Spacing.xxl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }.foregroundStyle(PBTheme.textOnDark)
                }
            }
            .toolbarBackground(PBTheme.midnight, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $isPeoplePickerPresented) {
            CollaboratorPickerView(excluding: viewerUID, selected: $invitees, title: "Menschen auswählen", selectionLimit: 8)
        }
        .fullScreenCover(isPresented: $isCriteriaPresented) {
            if let couple {
                CriteriaFormView(
                    couple: couple,
                    savedDateService: savedDateService,
                    profileCity: profileCity,
                    audience: PlanningAudience(mode: mode, invitees: invitees),
                    showsDismissButton: true,
                    onPlanSaved: onPlanSaved
                )
            } else {
                CriteriaFormView(
                    personalUID: viewerUID,
                    savedDateService: savedDateService,
                    profileCity: profileCity,
                    audience: PlanningAudience(mode: .group, invitees: invitees),
                    onPlanSaved: onPlanSaved
                )
            }
        }
    }

    private func modeCard(mode candidate: PlanningMode, title: String, detail: String, symbol: String) -> some View {
        Button { mode = candidate } label: {
            HStack(spacing: PBTheme.Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(mode == candidate ? PBTheme.midnight : PBTheme.textOnDark)
                    .frame(width: 48, height: 48)
                    .background(mode == candidate ? PBTheme.surface : PBTheme.routeSurfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
                    Text(detail).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: mode == candidate ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(mode == candidate ? PBTheme.accent : PBTheme.textOnDarkSecondary.opacity(0.7))
            }
            .padding(PBTheme.Spacing.md)
            .background(mode == candidate ? PBTheme.routeSurfaceRaised : PBTheme.routeSurface,
                        in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(mode == candidate ? PBTheme.accent.opacity(0.58) : .white.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func audienceSurface<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text(title).font(PBTheme.Typography.headline).foregroundStyle(PBTheme.textOnDark)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(PBTheme.Spacing.md)
        .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.card, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private func selectedPerson(_ person: PersonProfile) -> some View {
        HStack(spacing: 6) {
            Group {
                if let avatarPath = person.avatarPath { StorageImageView(path: avatarPath) }
                else { Text(String(person.displayName.prefix(1)).uppercased()).font(PBTheme.Typography.micro.weight(.bold)).foregroundStyle(PBTheme.midnight).frame(maxWidth: .infinity, maxHeight: .infinity).background(PBTheme.surface) }
            }
            .frame(width: 24, height: 24).clipShape(Circle())
            Text(person.displayName).font(PBTheme.Typography.caption.weight(.medium))
            Button { invitees.removeAll { $0.uid == person.uid } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }.buttonStyle(.plain)
        }
        .foregroundStyle(PBTheme.textOnDark)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(PBTheme.routeSurfaceRaised, in: Capsule())
    }
}
