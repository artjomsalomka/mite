import FirebaseFirestore
import XCTest
@testable import PerfectBoyfriend

final class DatePlanningCoreTests: XCTestCase {
    @MainActor
    func testAvailabilitySavesStayOrderedDuringRapidChanges() async {
        var completed: [GroupEventAvailabilityStatus] = []
        var started = false
        let service = GroupEventAvailabilityService { _, statuses, _, _ in
            if statuses["2000003600"] == .available {
                started = true
                try await Task.sleep(for: .milliseconds(100))
            }
            completed.append(statuses["2000003600"]!)
        }
        let first = Task { await service.save(eventId: "event", statuses: ["2000003600": .available], durationMinutes: 120, source: .manual) }
        while !started { await Task.yield() }
        let second = Task { await service.save(eventId: "event", statuses: ["2000003600": .unavailable], durationMinutes: 120, source: .manual) }
        let results = await [first.value, second.value]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(completed, [.available, .unavailable])
        XCTAssertFalse(service.isSaving)
        XCTAssertNil(service.errorMessage)
    }

    @MainActor
    func testAvailabilityQueueRecoversAfterFailure() async {
        var attempts = 0
        let service = GroupEventAvailabilityService { _, _, _, _ in
            attempts += 1
            if attempts == 1 { throw TimeoutError.timedOut }
        }
        let failed = await service.save(eventId: "event", statuses: ["2000003600": .available], durationMinutes: 120, source: .manual)
        XCTAssertFalse(failed)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertFalse(service.isSaving)
        let retried = await service.save(eventId: "event", statuses: ["2000003600": .maybe], durationMinutes: 120, source: .manual)
        XCTAssertTrue(retried)
        XCTAssertNil(service.errorMessage)
        XCTAssertFalse(service.isSaving)
    }

    func testTimeFinderDoesNotReuseAvailabilityForDifferentDuration() {
        let slot = GroupEventTimeSlot(start: Date(timeIntervalSince1970: 2_000_000_000), durationMinutes: 240)
        let response = GroupEventAvailability(uid: "a", slotStatuses: [slot.storageKey: "available"],
            durationMinutes: 120, source: .calendar, updatedAt: .init(date: Date()))
        XCTAssertNil(response.status(for: slot))
        XCTAssertTrue(GroupEventTimeFinder.suggestions(slots: [slot], responses: [response], eligibleUIDs: ["a"]).isEmpty)
    }

    func testTimeFinderUsesLatestResponseAndUniqueParticipants() {
        let slot = GroupEventTimeSlot(start: Date(timeIntervalSince1970: 2_000_000_000), durationMinutes: 120)
        let older = GroupEventAvailability(uid: "a", slotStatuses: [slot.storageKey: "unavailable"],
            durationMinutes: 120, source: .manual, updatedAt: .init(seconds: 100, nanoseconds: 0))
        var newer = older
        newer.slotStatuses[slot.storageKey] = "available"
        newer.updatedAt = .init(seconds: 101, nanoseconds: 0)
        let result = GroupEventTimeFinder.suggestions(slots: [slot], responses: [newer, older], eligibleUIDs: ["a", "a"])
        XCTAssertEqual(result.first?.availableCount, 1)
        XCTAssertEqual(result.first?.participantCount, 1)
        XCTAssertTrue(GroupEventTimeFinder.suggestions(slots: [slot], responses: [newer], eligibleUIDs: ["a"], limit: -1).isEmpty)
    }

    func testAvailabilityPayloadKeepsVisibleEditsBeforeOldWeeks() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let saved = Dictionary(uniqueKeysWithValues: (1...120).map { (String(2_000_000_000 + $0 * 3_600), "available") })
        let visible = String(2_000_000_000 + 14 * 86_400)
        let payload = GroupEventAvailabilityPayload.make(local: [visible: .unavailable], saved: saved,
            preferredKeys: [visible], now: now)
        XCTAssertEqual(payload.count, 120)
        XCTAssertEqual(payload[visible], .unavailable)
        XCTAssertNotNil(payload[String(2_000_000_000 + 3_600)])
        XCTAssertNil(payload[String(2_000_000_000 + 120 * 3_600)])
        XCTAssertEqual(payload, GroupEventAvailabilityPayload.make(local: [visible: .unavailable], saved: saved,
            preferredKeys: [visible], now: now))
    }

    func testAvailabilityPayloadDropsInvalidAndExpiredSlots() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let result = GroupEventAvailabilityPayload.make(local: ["invalid": .available, "1999999999": .maybe,
            "2000000060": .available, String(2_000_000_000 + 90 * 86_400): .available],
            saved: ["2000003600": "unavailable", "2000007200": "unsupported"], preferredKeys: [], now: now)
        XCTAssertEqual(result, ["2000003600": .unavailable])
    }

    func testCalendarQueryIncludesTravelBufferOutsideCandidateWindow() throws {
        let slot = GroupEventTimeSlot(start: Date(timeIntervalSince1970: 2_000_000_000), durationMinutes: 120)
        let range = try XCTUnwrap(CalendarAvailabilityService.queryRange(for: [slot]))
        XCTAssertEqual(range.start, slot.start.addingTimeInterval(-900))
        XCTAssertEqual(range.end, slot.end.addingTimeInterval(900))
        XCTAssertNil(CalendarAvailabilityService.queryRange(for: []))
    }

    func testCalendarWeekdaysStayGermanOnNonGermanDevices() {
        XCTAssertEqual(PBLocalization.shortWeekdaySymbolsStartingMonday, ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"])
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(date.miteAbbreviatedDateTimeText.contains(" at "))
    }

    func testUntouchedCriteriaAreImmediatelyValidForServerContract() throws {
        let criteria = CriteriaDefaultsProvider.defaultCriteria(city: "Marburg", dietaryPreferences: ["vegetarisch"])

        XCTAssertEqual(criteria.city, "Marburg")
        XCTAssertEqual(criteria.budget, .mittel)
        XCTAssertEqual(criteria.moods, [.entspannt])
        XCTAssertEqual(criteria.indoorOutdoor, .egal)
        XCTAssertEqual(criteria.durationMinutes, 180)
        XCTAssertEqual(criteria.mobility, .auto)
        XCTAssertEqual(criteria.radiusKm, 20)
        XCTAssertEqual(criteria.planningMode, .date)
        XCTAssertEqual(criteria.participantCount, 2)
        XCTAssertEqual(criteria.dietaryPreferences, ["vegetarisch"])
    }

    func testDateCriteriaEncodingMatchesCallablePayload() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let criteria = DateCriteria(
            city: "Marburg",
            budget: .gehoben,
            moods: [.kulturell, .kulinarisch],
            indoorOutdoor: .drinnen,
            date: date,
            time: "19:30",
            durationMinutes: 210,
            occasion: "Geburtstag",
            dietaryPreferences: ["vegan"],
            mobility: .oepnv,
            radiusKm: 10,
            planningMode: .group,
            participantCount: 5
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(criteria)) as? [String: Any])
        XCTAssertEqual(object["city"] as? String, "Marburg")
        XCTAssertEqual(object["planningMode"] as? String, "group")
        XCTAssertEqual(object["participantCount"] as? Int, 5)
        XCTAssertEqual(object["radiusKm"] as? Double, 10)
        XCTAssertEqual(object["time"] as? String, "19:30")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(object["date"] as? String)))
    }

    func testLegacyCriteriaDecodeToSafeDateDefaults() throws {
        let json = Data(#"{"city":"Marburg","budget":"mittel","moods":["entspannt"],"indoorOutdoor":"egal","date":"2026-09-20T17:00:00Z","time":"19:00","durationMinutes":180,"occasion":"spontanes Date","dietaryPreferences":[],"mobility":"auto","radiusKm":20}"#.utf8)

        let criteria = try JSONDecoder().decode(DateCriteria.self, from: json)

        XCTAssertEqual(criteria.planningMode, .date)
        XCTAssertEqual(criteria.participantCount, 2)
    }

    func testPlanningScopeKeepsPersonalAndPairHistoriesSeparate() {
        XCTAssertEqual(DatePlanningScope.couple(id: "pair").id, "pair")
        XCTAssertEqual(DatePlanningScope.personal(id: "person").dateHistoryTitle, "Deine Pläne")
        XCTAssertTrue(DatePlanningScope.singleMatch(id: "match").isFirstMeeting)
        XCTAssertFalse(DatePlanningScope.couple(id: "pair").isFirstMeeting)
    }

    func testPlanningAudienceNeverCreatesOnePersonGroup() {
        let audience = PlanningAudience(mode: .group, invitees: [])

        XCTAssertEqual(audience.participantCount, 2)
        XCTAssertEqual(audience.suggestionHeadline, "Für eure Runde entdeckt")
    }

    func testGroupMoodOptionsReplaceRomanceWithSocialEnergy() {
        XCTAssertTrue(Mood.options(for: .date).contains(.romantisch))
        XCTAssertFalse(Mood.options(for: .date).contains(.gesellig))
        XCTAssertFalse(Mood.options(for: .group).contains(.romantisch))
        XCTAssertTrue(Mood.options(for: .group).contains(.gesellig))
    }

    func testBudgetGuidanceIsConcreteAndPerPerson() {
        for budget in BudgetLevel.allCases {
            XCTAssertTrue(budget.priceRange.contains("€"))
            XCTAssertTrue(budget.priceRange.contains("p. P."))
        }
    }

    func testExpenseCalculatorReducesGroupLedgerToMinimalTransfers() {
        let now = FirebaseFirestore.Timestamp(date: Date())
        let expenses = [
            GroupEventExpense(
                title: "Ufercafé",
                amountMinor: 6_000,
                currency: "EUR",
                paidByUid: "member-a",
                participantUids: ["member-a", "lea", "finn"],
                sharesByUid: ["member-a": 2_000, "lea": 2_000, "finn": 2_000],
                createdByUid: "member-a",
                status: .active,
                createdAt: now,
                updatedAt: now
            ),
            GroupEventExpense(
                title: "Taxi",
                amountMinor: 1_500,
                currency: "EUR",
                paidByUid: "lea",
                participantUids: ["member-a", "lea", "finn"],
                sharesByUid: ["member-a": 500, "lea": 500, "finn": 500],
                createdByUid: "lea",
                status: .active,
                createdAt: now,
                updatedAt: now
            ),
        ]

        let result = GroupEventExpenseCalculator.settlements(expenses: expenses, payments: [])

        XCTAssertEqual(result.reduce(0) { $0 + $1.amountMinor }, 3_500)
        XCTAssertEqual(result.filter { $0.toUid == "member-a" }.reduce(0) { $0 + $1.amountMinor }, 3_500)
    }

    func testMarkedPaymentReducesOpenSettlement() {
        let now = FirebaseFirestore.Timestamp(date: Date())
        let expense = GroupEventExpense(
            title: "Kaffee",
            amountMinor: 2_000,
            currency: "EUR",
            paidByUid: "lea",
            participantUids: ["lea", "finn"],
            sharesByUid: ["lea": 1_000, "finn": 1_000],
            createdByUid: "lea",
            status: .active,
            createdAt: now,
            updatedAt: now
        )
        let payment = GroupEventSettlementRecord(
            fromUid: "finn",
            toUid: "lea",
            amountMinor: 1_000,
            currency: "EUR",
            status: .markedPaid,
            createdAt: now,
            confirmedAt: nil
        )

        XCTAssertTrue(GroupEventExpenseCalculator.settlements(expenses: [expense], payments: [payment]).isEmpty)
    }

    func testTimeFinderRanksSlotWithoutConflictsFirst() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = GroupEventTimeSlot(start: start, durationMinutes: 120)
        let second = GroupEventTimeSlot(start: start.addingTimeInterval(7_200), durationMinutes: 120)
        let timestamp = FirebaseFirestore.Timestamp(date: Date())
        let responses = [
            GroupEventAvailability(uid: "a", slotStatuses: [first.storageKey: "available", second.storageKey: "available"], durationMinutes: 120, source: .manual, updatedAt: timestamp),
            GroupEventAvailability(uid: "b", slotStatuses: [first.storageKey: "available", second.storageKey: "unavailable"], durationMinutes: 120, source: .manual, updatedAt: timestamp),
        ]

        let result = GroupEventTimeFinder.suggestions(slots: [second, first], responses: responses, eligibleUIDs: ["a", "b"])

        XCTAssertEqual(result.first?.slot, first)
        XCTAssertEqual(result.first?.everyoneCanAttend, true)
    }

    func testTimeFinderNeverSuggestsSlotsWhereSomeoneIsBusy() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let busy = GroupEventTimeSlot(start: start, durationMinutes: 120)
        let free = GroupEventTimeSlot(start: start.addingTimeInterval(86_400), durationMinutes: 120)
        let timestamp = FirebaseFirestore.Timestamp(date: Date())
        let allBusy = [
            GroupEventAvailability(uid: "a", slotStatuses: [busy.storageKey: "unavailable", free.storageKey: "unavailable"], durationMinutes: 120, source: .calendar, updatedAt: timestamp),
        ]
        XCTAssertTrue(GroupEventTimeFinder.suggestions(slots: [busy, free], responses: allBusy, eligibleUIDs: ["a"]).isEmpty)

        let oneFree = [
            GroupEventAvailability(uid: "a", slotStatuses: [busy.storageKey: "unavailable", free.storageKey: "available"], durationMinutes: 120, source: .calendar, updatedAt: timestamp),
        ]
        XCTAssertEqual(GroupEventTimeFinder.suggestions(slots: [busy, free], responses: oneFree, eligibleUIDs: ["a"]).map(\.slot), [free])
    }
}
