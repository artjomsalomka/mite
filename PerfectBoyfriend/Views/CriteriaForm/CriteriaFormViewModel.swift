import FirebaseFirestore
import Foundation

private struct CriteriaDefaultsLoadResult: Sendable {
    let city: String?
    let dietaryPreferences: [String]
}

@MainActor
final class CriteriaFormViewModel: ObservableObject {
    @Published var criteria: DateCriteria
    @Published var isLoadingDefaults = false
    @Published var isResolvingLocation = false
    @Published var locationErrorMessage: String?

    private let locationService = LocationService()

    init(initialCriteria: DateCriteria = CriteriaDefaultsProvider.defaultCriteria(city: "", dietaryPreferences: [])) {
        criteria = initialCriteria
        if criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let rememberedCity = PlannerLocationDefaults.lastSelectedCity {
            criteria.city = rememberedCity
        }
    }

    /// Best-effort prefill: current city via CoreLocation, plus both partners' dietary defaults.
    /// A profile or recently chosen planning city always wins over the device position. This is
    /// particularly important in the Simulator, whose default coordinate is San Francisco.
    /// `withTimeout` intentionally runs the work independently instead of a task group: a
    /// task-group scope waits for every child to finish, but CoreLocation and Firestore can keep
    /// an interrupted request alive after cancellation and would otherwise retain the overlay.
    func loadDefaults(memberUids: [String]) async {
        let initialDietaryPreferences = criteria.dietaryPreferences
        isLoadingDefaults = true
        defer { isLoadingDefaults = false }

        locationErrorMessage = nil
        do {
            let locationService = locationService
            let defaults = try await withTimeout(seconds: 6) {
                await Self.fetchDefaults(locationService: locationService, memberUids: memberUids)
            }
            guard !Task.isCancelled else { return }
            if criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let city = defaults.city {
                selectCity(city)
            } else if criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationErrorMessage = "Standort konnte nicht ermittelt werden — bitte Stadt manuell eingeben."
            }
            if criteria.dietaryPreferences == initialDietaryPreferences {
                criteria.dietaryPreferences = defaults.dietaryPreferences
            }
        } catch {
            guard !Task.isCancelled else { return }
            if criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationErrorMessage = "Standort konnte nicht ermittelt werden — bitte Stadt manuell eingeben."
            }
        }
    }

    func selectCity(_ city: String) {
        let cleaned = LocationService.normalizedCityName(city)
        guard !cleaned.isEmpty else { return }
        criteria.city = cleaned
        PlannerLocationDefaults.store(city: cleaned)
        locationErrorMessage = nil
    }

    func commitTypedCity() {
        selectCity(criteria.city)
    }

    /// The planning confirmation is intentionally usable without opening every setting.
    /// If the user has no saved/profile city yet, we make one best-effort location request here;
    /// only a denied or unavailable location opens the focused city picker.
    func prepareForGeneration() async -> Bool {
        normalizeGenerationDefaults()
        commitTypedCity()
        guard criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        await useCurrentLocation()
        return !criteria.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Defensive normalization protects active sheets that were opened by an older build with
    /// the now-invalid 15 km default. New forms already start with valid values.
    private func normalizeGenerationDefaults() {
        let allowedRadii: [Double] = [2, 5, 10, 20, 35, 50]
        if !allowedRadii.contains(criteria.radiusKm) {
            criteria.radiusKm = allowedRadii.min(by: {
                abs($0 - criteria.radiusKm) < abs($1 - criteria.radiusKm)
            }) ?? 20
        }
        if criteria.moods.isEmpty {
            criteria.moods = [.entspannt]
        }
    }

    func useCurrentLocation() async {
        guard !isResolvingLocation else { return }
        isResolvingLocation = true
        defer { isResolvingLocation = false }
        do {
            // Separate from the background default lookup: concurrent requests must not
            // overwrite the same CoreLocation continuation or leave confirmation spinning.
            let service = LocationService()
            let city = try await withTimeout(seconds: 8) {
                try await service.requestCurrentCity()
            }
            selectCity(city)
        } catch {
            locationErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Standort konnte nicht ermittelt werden — bitte Stadt manuell eingeben."
        }
    }

    func toggleMood(_ mood: Mood) {
        if let index = criteria.moods.firstIndex(of: mood) {
            criteria.moods.remove(at: index)
        } else {
            criteria.moods.append(mood)
        }
    }

    private static func fetchDefaults(
        locationService: LocationService,
        memberUids: [String]
    ) async -> CriteriaDefaultsLoadResult {
        async let city: String? = try? await locationService.requestCurrentCity()
        async let dietaryPreferences = fetchCombinedDietaryPreferences(memberUids: memberUids)
        return await CriteriaDefaultsLoadResult(city: city, dietaryPreferences: dietaryPreferences)
    }

    private static func fetchCombinedDietaryPreferences(memberUids: [String]) async -> [String] {
        var combined = Set<String>()
        for uid in memberUids {
            guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
                  let user = try? snapshot.data(as: AppUser.self) else { continue }
            combined.formUnion(user.dietaryDefault)
        }
        return Array(combined).sorted()
    }
}
