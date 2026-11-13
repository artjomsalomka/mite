import FirebaseFunctions
import Foundation

struct FollowedPerson: Identifiable, Equatable {
    let uid: String
    let displayName: String
    let handle: String
    let city: String
    let avatarPath: String?
    let linkedCoupleId: String?
    var id: String { uid }
}

/// Follow state belongs to the signed-in person. Couple follows remain available for legacy
/// pair-only profiles, but new personal social surfaces use this service exclusively.
@MainActor
final class PersonFollowService: ObservableObject {
    @Published private(set) var followingUIDs: Set<String> = []
    @Published private(set) var followingPeople: [FollowedPerson] = []
    @Published private(set) var blockedUIDs: Set<String> = []
    @Published private(set) var blockedByMeUIDs: Set<String> = []
    @Published private(set) var blockedMeUIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published var actionError: String?

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let callable = Functions.functions().httpsCallable("getViewerPersonSocialState")
            let result = try await withTimeout(seconds: 15) { try await callable.call() }
            guard let data = result.data as? [String: Any] else { return }
            followingUIDs = Set(data["followingUids"] as? [String] ?? [])
            followingPeople = (data["followingPeople"] as? [[String: Any]] ?? []).compactMap { item in
                guard let uid = item["uid"] as? String,
                      let displayName = item["displayName"] as? String,
                      let handle = item["handle"] as? String else { return nil }
                return FollowedPerson(
                    uid: uid,
                    displayName: displayName,
                    handle: handle,
                    city: item["city"] as? String ?? "",
                    avatarPath: item["avatarPath"] as? String,
                    linkedCoupleId: item["linkedCoupleId"] as? String
                )
            }
            .sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }
            blockedByMeUIDs = Set(data["blockedByMeUids"] as? [String] ?? [])
            blockedMeUIDs = Set(data["blockedMeUids"] as? [String] ?? [])
            blockedUIDs = blockedByMeUIDs.union(blockedMeUIDs)
        } catch {
            // Browsing profiles remains useful if the private relationship snapshot is delayed.
            print("⚠️ personal follow state error: \(error)")
        }
    }

    func toggle(targetUID: String) async {
        let functionName = followingUIDs.contains(targetUID) ? "unfollowPerson" : "followPerson"
        do {
            let callable = Functions.functions().httpsCallable(functionName)
            let result = try await withTimeout(seconds: 15) {
                try await callable.call(["targetUid": targetUID])
            }
            guard let data = result.data as? [String: Any], let isFollowing = data["isFollowing"] as? Bool else { return }
            if isFollowing {
                followingUIDs.insert(targetUID)
                // The callable intentionally returns only a boolean. Refreshing once here keeps
                // the private relationship graph hidden while the “Folge ich” list updates at
                // the same moment as the button state.
                await refresh()
            } else {
                followingUIDs.remove(targetUID)
                followingPeople.removeAll { $0.uid == targetUID }
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func block(targetUID: String) async {
        await performSafetyAction(functionName: "blockSocialProfile", targetUID: targetUID, expectedBlocked: true)
    }

    func unblock(targetUID: String) async {
        await performSafetyAction(functionName: "unblockSocialProfile", targetUID: targetUID, expectedBlocked: false)
    }

    func report(targetUID: String) async {
        do {
            let callable = Functions.functions().httpsCallable("reportSocialProfile")
            _ = try await withTimeout(seconds: 15) { try await callable.call(["targetUid": targetUID, "reason": "profile"]) }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performSafetyAction(functionName: String, targetUID: String, expectedBlocked: Bool) async {
        do {
            let callable = Functions.functions().httpsCallable(functionName)
            _ = try await withTimeout(seconds: 15) { try await callable.call(["targetUid": targetUID]) }
            if expectedBlocked {
                blockedUIDs.insert(targetUID)
                blockedByMeUIDs.insert(targetUID)
                followingUIDs.remove(targetUID)
                followingPeople.removeAll { $0.uid == targetUID }
            } else {
                blockedUIDs.remove(targetUID)
                blockedByMeUIDs.remove(targetUID)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
