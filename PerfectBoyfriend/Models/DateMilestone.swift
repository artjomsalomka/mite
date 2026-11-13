import Foundation

struct DateMilestone: Identifiable, Equatable {
    let requiredRatedDates: Int
    let title: String
    let subtitle: String
    let symbolName: String

    var id: Int { requiredRatedDates }

    func isUnlocked(with ratedDateCount: Int) -> Bool {
        ratedDateCount >= requiredRatedDates
    }
}

enum CoupleMilestones {
    static let all: [DateMilestone] = [
        DateMilestone(
            requiredRatedDates: 1,
            title: "Erstes Kapitel",
            subtitle: "Euer erstes gemeinsames Date bewertet",
            symbolName: "sparkles"
        ),
        DateMilestone(
            requiredRatedDates: 5,
            title: "Date-Duo",
            subtitle: "Fünf gemeinsame Dates erlebt",
            symbolName: "figure.2.and.child.holdinghands"
        ),
        DateMilestone(
            requiredRatedDates: 10,
            title: "Kleine Tradition",
            subtitle: "Zehn Erinnerungen gesammelt",
            symbolName: "heart.text.square"
        ),
        DateMilestone(
            requiredRatedDates: 25,
            title: "Gemeinsame Geschichte",
            subtitle: "25 Dates miteinander erlebt",
            symbolName: "book.closed.fill"
        ),
    ]
}
