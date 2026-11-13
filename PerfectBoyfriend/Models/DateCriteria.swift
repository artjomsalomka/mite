import Foundation

/// Mirrors DateCriteriaPayload in functions/src/dateSuggestions/types.ts exactly — raw values
/// and field names must stay in sync since this is encoded straight into the callable Function
/// request.
enum BudgetLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case guenstig, mittel, gehoben
    var id: String { rawValue }
    var label: String {
        switch self {
        case .guenstig: return "Günstig"
        case .mittel: return "Mittel"
        case .gehoben: return "Gehoben"
        }
    }

    /// Concrete per-person amounts (whole plan: food, drinks, entry) so "Mittel" means something.
    /// The same wording is sent to the model so its picks match what the person saw.
    var priceRange: String {
        switch self {
        case .guenstig: return "bis ca. 20 € p. P."
        case .mittel: return "ca. 20–45 € p. P."
        case .gehoben: return "ab ca. 45 € p. P."
        }
    }
}

enum IndoorOutdoor: String, Codable, CaseIterable, Identifiable {
    case drinnen, draussen, egal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .drinnen: return "Drinnen"
        case .draussen: return "Draußen"
        case .egal: return "Egal"
        }
    }
}

enum Mobility: String, Codable, CaseIterable, Identifiable {
    case zufuss, oepnv, auto
    var id: String { rawValue }
    var label: String {
        switch self {
        case .zufuss: return "Zu Fuß"
        case .oepnv: return "ÖPNV"
        case .auto: return "Auto"
        }
    }
}

enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case aktiv, entspannt, romantisch, kulinarisch, kulturell, abenteuerlich, gesellig
    var id: String { rawValue }

    /// "Romantisch" only fits two people on a date; "Gesellig" only fits a group. Singles and
    /// couples never see the group mood and vice versa.
    static func options(for mode: PlanningMode) -> [Mood] {
        switch mode {
        case .date: return [.aktiv, .entspannt, .romantisch, .kulinarisch, .kulturell, .abenteuerlich]
        case .group: return [.aktiv, .entspannt, .gesellig, .kulinarisch, .kulturell, .abenteuerlich]
        }
    }
    var label: String {
        switch self {
        case .aktiv: return "Aktiv"
        case .entspannt: return "Entspannt"
        case .romantisch: return "Romantisch"
        case .kulinarisch: return "Kulinarisch"
        case .kulturell: return "Kulturell"
        case .abenteuerlich: return "Abenteuerlich"
        case .gesellig: return "Gesellig"
        }
    }
}

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case spontan = "spontanes Date"
    case jahrestag = "Jahrestag"
    case erstesDate = "erstes Date"
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

struct DateCriteria: Codable, Equatable {
    var city: String
    var budget: BudgetLevel
    var moods: [Mood]
    var indoorOutdoor: IndoorOutdoor
    var date: Date
    var time: String // "HH:mm", kept separate from `date` to match the server contract exactly
    var durationMinutes: Int
    var occasion: String
    var dietaryPreferences: [String]
    var mobility: Mobility
    var radiusKm: Double
    /// Explicit planning context lets the recommendation engine choose places and pacing that
    /// work for a shared group rather than merely changing the UI copy.
    var planningMode: PlanningMode
    var participantCount: Int

    /// The callable Function expects `date` as an ISO 8601 string, not a Firestore Timestamp —
    /// it's only ever read by Claude as prompt text, never queried on.
    private enum CodingKeys: String, CodingKey {
        case city, budget, moods, indoorOutdoor, date, time, durationMinutes, occasion, dietaryPreferences, mobility, radiusKm, planningMode, participantCount
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(city, forKey: .city)
        try container.encode(budget, forKey: .budget)
        try container.encode(moods, forKey: .moods)
        try container.encode(indoorOutdoor, forKey: .indoorOutdoor)
        try container.encode(ISO8601DateFormatter().string(from: date), forKey: .date)
        try container.encode(time, forKey: .time)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(occasion, forKey: .occasion)
        try container.encode(dietaryPreferences, forKey: .dietaryPreferences)
        try container.encode(mobility, forKey: .mobility)
        try container.encode(radiusKm, forKey: .radiusKm)
        try container.encode(planningMode, forKey: .planningMode)
        try container.encode(participantCount, forKey: .participantCount)
    }

    init(city: String, budget: BudgetLevel, moods: [Mood], indoorOutdoor: IndoorOutdoor, date: Date, time: String, durationMinutes: Int, occasion: String, dietaryPreferences: [String], mobility: Mobility, radiusKm: Double, planningMode: PlanningMode = .date, participantCount: Int = 2) {
        self.city = city
        self.budget = budget
        self.moods = moods
        self.indoorOutdoor = indoorOutdoor
        self.date = date
        self.time = time
        self.durationMinutes = durationMinutes
        self.occasion = occasion
        self.dietaryPreferences = dietaryPreferences
        self.mobility = mobility
        self.radiusKm = radiusKm
        self.planningMode = planningMode
        self.participantCount = participantCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        city = try container.decode(String.self, forKey: .city)
        budget = try container.decode(BudgetLevel.self, forKey: .budget)
        moods = try container.decode([Mood].self, forKey: .moods)
        indoorOutdoor = try container.decode(IndoorOutdoor.self, forKey: .indoorOutdoor)
        let dateString = try container.decode(String.self, forKey: .date)
        date = ISO8601DateFormatter().date(from: dateString) ?? Date()
        time = try container.decode(String.self, forKey: .time)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        occasion = try container.decode(String.self, forKey: .occasion)
        dietaryPreferences = try container.decode([String].self, forKey: .dietaryPreferences)
        mobility = try container.decode(Mobility.self, forKey: .mobility)
        radiusKm = try container.decode(Double.self, forKey: .radiusKm)
        planningMode = try container.decodeIfPresent(PlanningMode.self, forKey: .planningMode) ?? .date
        participantCount = try container.decodeIfPresent(Int.self, forKey: .participantCount) ?? 2
    }
}
