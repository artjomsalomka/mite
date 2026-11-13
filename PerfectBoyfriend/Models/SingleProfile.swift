import FirebaseFirestore
import Foundation

struct SingleProfile: Codable, Identifiable, Equatable {
    @DocumentID var id: String?
    var uid: String
    var displayName: String
    var city: String
    var cityNormalized: String
    var bio: String
    var age: Int
    var preferredAgeMinimum: Int
    var preferredAgeMaximum: Int
    var interests: [String]
    var budgetPreference: BudgetLevel
    var moods: [Mood]
    var isMatchingActive: Bool
    var avatarPath: String?
    var isVerified: Bool?
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

struct SingleProfileDraft: Equatable {
    var displayName: String
    var city: String
    var bio: String
    var age: Int
    var preferredAgeMinimum: Int
    var preferredAgeMaximum: Int
    var interests: [String]
    var budgetPreference: BudgetLevel
    var moods: [Mood]
    var isMatchingActive: Bool
    var avatarPath: String?
    var removesAvatar: Bool

    init(profile: SingleProfile) {
        displayName = profile.displayName
        city = profile.city
        bio = profile.bio
        age = profile.age
        preferredAgeMinimum = profile.preferredAgeMinimum
        preferredAgeMaximum = profile.preferredAgeMaximum
        interests = profile.interests
        budgetPreference = profile.budgetPreference
        moods = profile.moods
        isMatchingActive = profile.isMatchingActive
        avatarPath = profile.avatarPath
        removesAvatar = false
    }

    init(suggestedName: String) {
        displayName = suggestedName
        city = ""
        bio = ""
        age = 25
        preferredAgeMinimum = 22
        preferredAgeMaximum = 32
        interests = []
        budgetPreference = .mittel
        moods = [.entspannt, .kulinarisch]
        isMatchingActive = true
        avatarPath = nil
        removesAvatar = false
    }
}

/// A deliberately small, server-sanitized candidate representation. It contains neither email,
/// phone number, exact location nor a birth date.
struct SingleSuggestion: Codable, Identifiable, Equatable, Sendable {
    var uid: String
    var displayName: String
    var city: String
    var bio: String
    var age: Int
    var interests: [String]
    var budgetPreference: BudgetLevel
    var moods: [Mood]
    var isVerified: Bool
    var avatarPath: String?
    var commonInterestCount: Int

    var id: String { uid }
}

struct SingleMatchPreview: Codable, Identifiable, Equatable, Sendable {
    var matchId: String
    var profile: SingleSuggestion
    var matchedAtMilliseconds: Double
    var lastActivityAtMilliseconds: Double
    var hasUnreadMessage: Bool

    var id: String { matchId }
}
