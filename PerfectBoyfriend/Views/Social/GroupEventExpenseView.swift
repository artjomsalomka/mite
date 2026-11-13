import SwiftUI

struct GroupEventExpenseView: View {
    let event: GroupEvent
    let uid: String

    @StateObject private var service = GroupEventExpenseService()
    @State private var isExpenseSheetPresented = false
    @State private var isPaymentLinkSheetPresented = false
    @State private var selectedSettlement: GroupEventSettlementSuggestion?

    private var eventID: String { event.id ?? "" }
    private var activeExpenses: [GroupEventExpense] { service.expenses.filter { $0.status == .active } }
    private var settlements: [GroupEventSettlementSuggestion] {
        GroupEventExpenseCalculator.settlements(expenses: activeExpenses, payments: service.payments)
    }
    private var openAmount: Int { settlements.reduce(0) { $0 + $1.amountMinor } }
    private var pendingConfirmations: [GroupEventSettlementRecord] {
        service.payments.filter { $0.status == .markedPaid && $0.toUid == uid }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                heading
                if !pendingConfirmations.isEmpty { confirmationSection }
                expensesSection
                settlementsSection
                addButton
                paymentLinkButton
            }
            .padding(.horizontal, PBTheme.Spacing.md)
            .padding(.top, PBTheme.Spacing.md)
            .padding(.bottom, PBTheme.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .task(id: eventID) { service.startListening(eventId: eventID) }
        .onDisappear { service.stopListening() }
        .sheet(isPresented: $isExpenseSheetPresented) {
            GroupEventExpenseComposer(event: event) { title, amount, paidBy, participants, shares in
                await service.addExpense(
                    eventId: eventID,
                    title: title,
                    amountMinor: amount,
                    paidByUid: paidBy,
                    participantUIDs: participants,
                    sharesByUID: shares
                )
            }
            .presentationDetents([.large])
            .presentationBackground(PBTheme.midnight)
        }
        .sheet(isPresented: $isPaymentLinkSheetPresented) {
            GroupEventPaymentLinkSheet { link in
                await service.savePayPalMe(eventId: eventID, url: link)
            }
            .presentationDetents([.medium])
            .presentationBackground(PBTheme.midnightRaised)
        }
        .sheet(item: $selectedSettlement) { settlement in
            GroupEventPaymentActionSheet(
                settlement: settlement,
                payee: participant(settlement.toUid),
                paymentLink: service.paymentLinksByUID[settlement.toUid]
            ) {
                await service.markPaid(eventId: eventID, suggestion: settlement)
            }
            .presentationDetents([.medium])
            .presentationBackground(PBTheme.midnightRaised)
        }
        .alert("Gemeinsame Kasse", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Gemeinsame Kasse")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(PBTheme.textOnDark)
            HStack(spacing: PBTheme.Spacing.md) {
                Text("\(openAmount.miteCurrency()) offen")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PBTheme.textOnDark)
                Text("\(activeExpenses.count) \(activeExpenses.count == 1 ? "Ausgabe" : "Ausgaben")")
                    .font(PBTheme.Typography.body)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
            }
        }
    }

    private var expensesSection: some View {
        VStack(spacing: 0) {
            if activeExpenses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "eurosign.circle")
                        .font(.system(size: 28, weight: .light))
                    Text("Noch keine gemeinsamen Ausgaben")
                        .font(PBTheme.Typography.caption)
                }
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(activeExpenses.enumerated()), id: \.element.id) { index, expense in
                    expenseRow(expense)
                    if index < activeExpenses.count - 1 { Divider().overlay(PBTheme.controlBorder) }
                }
            }
        }
    }

    private func expenseRow(_ expense: GroupEventExpense) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol(for: expense.title))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(width: 44, height: 44)
                .background(PBTheme.controlSurfaceRaised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(PBTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(PBTheme.textOnDark)
                Text("Bezahlt von \(participant(expense.paidByUid)?.displayName ?? "Unbekannt")")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                GroupEventMiniAvatarStack(
                    people: expense.participantUids.compactMap(participant),
                    size: 19
                )
            }
            Spacer(minLength: 8)
            Text(expense.amountMinor.miteCurrency(code: expense.currency))
                .font(PBTheme.Typography.body.weight(.semibold))
                .foregroundStyle(PBTheme.textOnDark)
            Menu {
                if expense.createdByUid == uid || event.creatorUid == uid {
                    Button("Ausgabe stornieren", role: .destructive) {
                        guard let expenseID = expense.id else { return }
                        Task { _ = await service.voidExpense(eventId: eventID, expenseId: expenseID) }
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .frame(width: 22, height: 44)
            }
        }
        .padding(.vertical, 13)
    }

    private var settlementsSection: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text(settlements.isEmpty ? "Alles ausgeglichen" : "So ist es am einfachsten")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)

            if settlements.isEmpty {
                Label("Im Moment sind keine Zahlungen offen.", systemImage: "checkmark.circle")
                    .font(PBTheme.Typography.caption)
                    .foregroundStyle(PBTheme.textOnDarkSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(settlements) { settlement in
                    HStack(spacing: 11) {
                        GroupEventParticipantAvatar(person: participant(settlement.fromUid), size: 35)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(shortName(settlement.fromUid)) zahlt \(shortName(settlement.toUid))")
                                .font(PBTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                            Text(settlement.amountMinor.miteCurrency(code: settlement.currency))
                                .font(PBTheme.Typography.micro)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        Spacer()
                        if settlement.fromUid == uid {
                            Button("Bezahlen") { selectedSettlement = settlement }
                                .font(PBTheme.Typography.micro.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(PBTheme.controlSelected, in: Capsule())
                                .buttonStyle(.plain)
                        } else {
                            Text("Offen")
                                .font(PBTheme.Typography.micro)
                                .foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                    }
                    .padding(12)
                    .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small).stroke(PBTheme.controlBorder, lineWidth: 1) }
                }
            }
        }
    }

    private var confirmationSection: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.sm) {
            Text("Zahlung bestätigen")
                .font(PBTheme.Typography.headline)
                .foregroundStyle(PBTheme.textOnDark)
            ForEach(pendingConfirmations) { payment in
                HStack {
                    Text("\(shortName(payment.fromUid)) hat \(payment.amountMinor.miteCurrency()) markiert")
                        .font(PBTheme.Typography.caption)
                        .foregroundStyle(PBTheme.textOnDark)
                    Spacer()
                    Button("Erhalten") {
                        guard let paymentID = payment.id else { return }
                        Task { _ = await service.confirm(eventId: eventID, settlementId: paymentID) }
                    }
                    .font(PBTheme.Typography.micro.weight(.semibold))
                    .foregroundStyle(PBTheme.midnight)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(PBTheme.surfaceOnDark, in: Capsule())
                }
                .padding(12)
                .background(PBTheme.accentMuted, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small))
            }
        }
    }

    private var addButton: some View {
        Button { isExpenseSheetPresented = true } label: {
            Label("Ausgabe hinzufügen", systemImage: "receipt")
                .font(PBTheme.Typography.body.weight(.semibold))
                .foregroundStyle(PBTheme.textOnDark)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(PBTheme.controlSelected, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(event.status == .cancelled || service.isWorking)
    }

    private var paymentLinkButton: some View {
        Button { isPaymentLinkSheetPresented = true } label: {
            Label(service.paymentLinksByUID[uid] == nil ? "PayPal.Me hinterlegen" : "Zahlungslink ändern", systemImage: "link")
                .font(PBTheme.Typography.caption)
                .foregroundStyle(PBTheme.textOnDarkSecondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func participant(_ uid: String) -> GroupEventParticipant? {
        event.participants.first { $0.uid == uid }
    }

    private func shortName(_ uid: String) -> String {
        participant(uid)?.displayName.components(separatedBy: " ").first ?? "Person"
    }

    private func symbol(for title: String) -> String {
        let lowered = title.lowercased()
        if lowered.contains("taxi") || lowered.contains("fahrt") { return "car.side" }
        if lowered.contains("essen") || lowered.contains("restaurant") { return "fork.knife" }
        if lowered.contains("kaffee") || lowered.contains("café") || lowered.contains("cafe") { return "cup.and.saucer" }
        if lowered.contains("ticket") || lowered.contains("eintritt") { return "ticket" }
        return "receipt"
    }
}

private struct GroupEventMiniAvatarStack: View {
    let people: [GroupEventParticipant]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -5) {
            ForEach(people.prefix(5)) { person in
                GroupEventParticipantAvatar(person: person, size: size)
                    .overlay { Circle().stroke(PBTheme.midnight, lineWidth: 1) }
            }
        }
    }
}

private struct GroupEventExpenseComposer: View {
    let event: GroupEvent
    let onSave: (String, Int, String, [String], [String: Int]) async -> Bool

    @State private var title = ""
    @State private var amountText = ""
    @State private var paidByUid: String
    @State private var selectedUIDs: Set<String>
    @State private var splitMode = 0
    @State private var customAmounts: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(event: GroupEvent, onSave: @escaping (String, Int, String, [String], [String: Int]) async -> Bool) {
        self.event = event
        self.onSave = onSave
        _paidByUid = State(initialValue: event.creatorUid)
        _selectedUIDs = State(initialValue: Set(event.participants.filter { $0.status != .declined }.map(\.uid)))
    }

    private var amountMinor: Int? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }

    var body: some View {
        NavigationStack {
            PBScreenContainer {
                ScrollView {
                    VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
                        Text("Neue Ausgabe")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(PBTheme.textOnDark)

                        inputField("Wofür?", text: $title)
                        inputField("Betrag in €", text: $amountText, keyboard: .decimalPad)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bezahlt von").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                            Picker("Bezahlt von", selection: $paidByUid) {
                                ForEach(event.participants.filter { $0.status != .declined }) { person in
                                    Text(person.displayName).tag(person.uid)
                                }
                            }
                            .pickerStyle(.menu).tint(PBTheme.textOnDark)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Wer war beteiligt?").font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                            ForEach(event.participants.filter { $0.status != .declined }) { person in
                                Button { toggle(person.uid) } label: {
                                    HStack {
                                        GroupEventParticipantAvatar(person: person, size: 35)
                                        Text(person.displayName).foregroundStyle(PBTheme.textOnDark)
                                        Spacer()
                                        Image(systemName: selectedUIDs.contains(person.uid) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedUIDs.contains(person.uid) ? PBTheme.accent : PBTheme.textOnDarkSecondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Picker("Aufteilung", selection: $splitMode) {
                            Text("Gleichmäßig").tag(0)
                            Text("Individuell").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if splitMode == 1 {
                            VStack(spacing: 10) {
                                ForEach(event.participants.filter { selectedUIDs.contains($0.uid) }) { person in
                                    HStack {
                                        Text(person.displayName).foregroundStyle(PBTheme.textOnDark)
                                        Spacer()
                                        TextField("0,00 €", text: customBinding(person.uid))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .foregroundStyle(PBTheme.textOnDark)
                                            .frame(width: 100)
                                    }
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.warning)
                        }

                        Button { Task { await save() } } label: {
                            Text(isSaving ? "Speichert …" : "Ausgabe hinzufügen")
                                .font(PBTheme.Typography.body.weight(.semibold))
                                .foregroundStyle(PBTheme.textOnDark)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(PBTheme.controlSelected, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small))
                        }
                        .buttonStyle(.plain).disabled(isSaving)
                    }
                    .padding(PBTheme.Spacing.md)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }.foregroundStyle(PBTheme.textOnDark)
                }
            }
        }
    }

    private func inputField(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .font(PBTheme.Typography.body)
            .foregroundStyle(PBTheme.textOnDark)
            .padding(PBTheme.Spacing.md)
            .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small))
            .overlay { RoundedRectangle(cornerRadius: PBTheme.Radius.small).stroke(PBTheme.controlBorder, lineWidth: 1) }
    }

    private func toggle(_ uid: String) {
        if selectedUIDs.contains(uid) { selectedUIDs.remove(uid) } else { selectedUIDs.insert(uid) }
    }

    private func customBinding(_ uid: String) -> Binding<String> {
        Binding(get: { customAmounts[uid] ?? "" }, set: { customAmounts[uid] = $0 })
    }

    private func save() async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { errorMessage = "Gib der Ausgabe einen kurzen Namen."; return }
        guard let amountMinor else { errorMessage = "Gib einen gültigen Betrag ein."; return }
        let participants = Array(selectedUIDs).sorted()
        guard !participants.isEmpty else { errorMessage = "Wähle mindestens eine beteiligte Person."; return }
        let shares: [String: Int]
        if splitMode == 0 {
            shares = GroupEventExpenseCalculator.equalShares(amountMinor: amountMinor, participantUIDs: participants)
        } else {
            shares = Dictionary(uniqueKeysWithValues: participants.map { uid in
                let normalized = (customAmounts[uid] ?? "").replacingOccurrences(of: ",", with: ".")
                let decimal = Decimal(string: normalized) ?? 0
                return (uid, NSDecimalNumber(decimal: decimal * 100).intValue)
            })
            guard shares.values.reduce(0, +) == amountMinor else {
                errorMessage = "Die Einzelbeträge müssen zusammen \(amountMinor.miteCurrency()) ergeben."
                return
            }
        }
        isSaving = true
        defer { isSaving = false }
        if await onSave(cleanTitle, amountMinor, paidByUid, participants, shares) { dismiss() }
    }
}

private struct GroupEventPaymentLinkSheet: View {
    let onSave: (String) async -> Bool
    @State private var link = "https://paypal.me/"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
            Capsule().fill(PBTheme.textOnDarkSecondary.opacity(0.5)).frame(width: 38, height: 5).frame(maxWidth: .infinity)
            Text("Dein Zahlungslink")
                .font(.system(size: 28, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Text("Mite speichert keine PayPal-Zugangsdaten. Gruppenmitglieder erhalten nur diesen PayPal.Me-Link.")
                .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            TextField("https://paypal.me/deinname", text: $link)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDark)
                .padding(PBTheme.Spacing.md)
                .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.small))
            if let errorMessage { Text(errorMessage).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.warning) }
            Button {
                Task {
                    guard link.lowercased().hasPrefix("https://paypal.me/") else { errorMessage = "Bitte verwende einen vollständigen PayPal.Me-Link."; return }
                    isSaving = true; defer { isSaving = false }
                    if await onSave(link) { dismiss() }
                }
            } label: {
                Text(isSaving ? "Speichert …" : "Sicher hinterlegen")
                    .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                    .frame(maxWidth: .infinity, minHeight: 50).background(PBTheme.controlSelected, in: Capsule())
            }
            .buttonStyle(.plain).disabled(isSaving)
            Spacer()
        }
        .padding(PBTheme.Spacing.md)
    }
}

private struct GroupEventPaymentActionSheet: View {
    let settlement: GroupEventSettlementSuggestion
    let payee: GroupEventParticipant?
    let paymentLink: String?
    let onMarkPaid: () async -> Bool

    @State private var isMarking = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: PBTheme.Spacing.lg) {
            Capsule().fill(PBTheme.textOnDarkSecondary.opacity(0.5)).frame(width: 38, height: 5).frame(maxWidth: .infinity)
            Text("\(settlement.amountMinor.miteCurrency()) bezahlen")
                .font(.system(size: 28, weight: .light)).foregroundStyle(PBTheme.textOnDark)
            Text("an \(payee?.displayName ?? "die empfangende Person")")
                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)

            if let paymentURL {
                Button {
                    openURL(paymentURL)
                } label: {
                    Label("PayPal öffnen", systemImage: "arrow.up.right.square")
                        .font(PBTheme.Typography.body.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                        .frame(maxWidth: .infinity, minHeight: 50).background(PBTheme.controlSelected, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text("Die empfangende Person hat noch keinen PayPal.Me-Link hinterlegt.")
                    .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
            }

            Button {
                Task {
                    isMarking = true; defer { isMarking = false }
                    if await onMarkPaid() { dismiss() }
                }
            } label: {
                Text(isMarking ? "Wird markiert …" : "Als bezahlt markieren")
                    .font(PBTheme.Typography.caption.weight(.semibold)).foregroundStyle(PBTheme.textOnDark)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(PBTheme.routeSurfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain).disabled(isMarking)
            Spacer()
        }
        .padding(PBTheme.Spacing.md)
    }

    private var paymentURL: URL? {
        guard let paymentLink else { return nil }
        let base = paymentLink.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let amount = String(format: "%.2f", Double(settlement.amountMinor) / 100.0)
        return URL(string: "\(base)/\(amount)EUR")
    }
}

struct GroupEventParticipantAvatar: View {
    let person: GroupEventParticipant?
    let size: CGFloat

    var body: some View {
        Group {
            if let path = person?.avatarPath, !path.isEmpty {
                StorageImageView(path: path)
            } else {
                Text(String(person?.displayName.prefix(1) ?? "?").uppercased())
                    .font(.system(size: max(10, size * 0.34), weight: .bold))
                    .foregroundStyle(PBTheme.midnight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PBTheme.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(PBTheme.textOnDark.opacity(0.7), lineWidth: 0.8) }
    }
}
