import Foundation

/// Computes the sensible defaults that let the criteria form be filled in under a minute —
/// every value here stays editable in the form, this just decides the starting point.
enum CriteriaDefaultsProvider {
    static func defaultCriteria(city: String, dietaryPreferences: [String]) -> DateCriteria {
        DateCriteria(
            city: city,
            budget: .mittel,
            // A complete, calm evening is the neutral starting point. Every planning station therefore
            // has a meaningful value even when the couple changes none of the controls.
            moods: [.entspannt],
            indoorOutdoor: .egal,
            date: Date(),
            time: defaultTimeString(),
            durationMinutes: 180,
            occasion: Occasion.spontan.rawValue,
            dietaryPreferences: dietaryPreferences,
            mobility: .auto,
            // Keep this in lockstep with the server's allowed radii: 2, 5, 10, 20, 35, 50.
            // A former default of 15 made an untouched form fail backend validation.
            radiusKm: 20
        )
    }

    /// 19:00 if it's currently before 17:00, otherwise "now + 3h" rounded to the nearest half hour.
    static func defaultTimeString(now: Date = Date(), calendar: Calendar = .current) -> String {
        let currentHour = calendar.component(.hour, from: now)
        let target: Date
        if currentHour < 17 {
            target = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        } else {
            let plusThreeHours = calendar.date(byAdding: .hour, value: 3, to: now) ?? now
            // Round up to the next half hour via pure interval math — avoids reconstructing hour
            // components by hand, which breaks at the hour-23-rolling-to-24 edge case.
            let halfHour: TimeInterval = 30 * 60
            let epoch = plusThreeHours.timeIntervalSinceReferenceDate
            let roundedEpoch = (epoch / halfHour).rounded(.up) * halfHour
            target = Date(timeIntervalSinceReferenceDate: roundedEpoch)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: target)
    }
}
