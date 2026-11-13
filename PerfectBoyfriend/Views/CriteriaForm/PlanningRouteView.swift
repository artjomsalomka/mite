import SwiftUI
import UIKit

extension PlanningCriterion {
    static let routeOrder: [PlanningCriterion] = [.location, .time, .mood, .budget, .setting, .mobility, .details]

    func value(in criteria: DateCriteria) -> String {
        switch self {
        case .location: return criteria.city.isEmpty ? "Stadt auswählen" : criteria.city
        case .time:
            return "\(criteria.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE")))) · \(criteria.time)\n\(criteria.durationMinutes) Minuten"
        case .mood: return criteria.moods.isEmpty ? Mood.entspannt.label : criteria.moods.map(\.label).joined(separator: " · ")
        case .budget: return criteria.budget.label
        case .setting: return criteria.indoorOutdoor == .egal ? "Drinnen & draußen" : criteria.indoorOutdoor.label
        case .mobility: return "\(criteria.mobility.label) · \(Int(criteria.radiusKm)) km"
        case .details:
            let food = criteria.dietaryPreferences.isEmpty ? "Keine Essenswünsche" : criteria.dietaryPreferences.joined(separator: ", ")
            if criteria.planningMode == .group { return food }
            return "\(criteria.occasion.capitalized)\n\(food)"
        }
    }
}

@MainActor
final class PlanningRoutePresentation: ObservableObject {
    let world = DateRouteScene(count: PlanningCriterion.routeOrder.count, cardStyle: .planningDisc)
    @Published private(set) var progress: Float = 0
    private var renderedValues: [PlanningCriterion: String] = [:]

    var selectedIndex: Int { min(PlanningCriterion.routeOrder.count - 1, max(0, Int(progress.rounded()))) }
    var selectedCriterion: PlanningCriterion { PlanningCriterion.routeOrder[selectedIndex] }

    func travel(to value: Float, animated: Bool, reduceMotion: Bool) {
        progress = min(Float(PlanningCriterion.routeOrder.count - 1), max(0, value))
        world.move(to: progress, focus: nil, animated: animated && !reduceMotion)
    }

    func select(_ criterion: PlanningCriterion, reduceMotion: Bool) {
        guard let index = PlanningCriterion.routeOrder.firstIndex(of: criterion) else { return }
        progress = Float(index)
        world.move(to: progress, focus: index, animated: !reduceMotion)
    }

    func update(criteria: DateCriteria) {
        for (index, criterion) in PlanningCriterion.routeOrder.enumerated() {
            let value = criterion.value(in: criteria)
            guard renderedValues[criterion] != value else { continue }
            let renderer = ImageRenderer(content: PlanningStationArtwork(criterion: criterion, title: criterion.title(in: criteria.planningMode), value: value)
                .frame(width: 640, height: 640)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large))
            renderer.scale = 1
            renderer.isOpaque = true
            if let image = renderer.cgImage {
                world.setPhoto(image, at: index)
                renderedValues[criterion] = value
            }
        }
    }
}

/// Settings use original vector artwork, not photographs that could imply a chosen destination.
private struct PlanningStationArtwork: View {
    let criterion: PlanningCriterion
    let title: String
    let value: String

    var body: some View {
        ZStack {
            Color.white
            VStack(spacing: 20) {
                PlanningCriterionGlyph(criterion: criterion)
                    .frame(width: 27, height: 27)
                    .colorMultiply(Color(cgColor: DateRouteScene.navy))
                    .scaleEffect(3.8)
                    .frame(height: 128)
                Text(title)
                    .font(.system(size: 48, weight: .medium))
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(value)
                    .font(.system(size: 40, weight: .regular))
                    .lineLimit(3).minimumScaleFactor(0.75)
                    .foregroundStyle(Color(cgColor: DateRouteScene.navy).opacity(0.76))
            }
            .multilineTextAlignment(.center)
            .frame(width: 440, height: 430)
        }
        .foregroundStyle(Color(cgColor: DateRouteScene.navy))
    }
}

struct PlanningRouteView: View {
    @ObservedObject var route: PlanningRoutePresentation
    let criteria: DateCriteria
    let title: String
    let isPreparing: Bool
    let isActive: Bool
    let onSelect: (PlanningCriterion) -> Void
    let onGenerate: () -> Void
    var onClose: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        ZStack {
            Color(cgColor: DateRouteScene.navy).ignoresSafeArea()
            SpatialRouteSceneView(world: route.world, progress: route.progress, reduceMotion: reduceMotion,
                isActive: isActive && isVisible && scenePhase == .active,
                onSelect: { index in
                    guard PlanningCriterion.routeOrder.indices.contains(index) else { return }
                    onSelect(PlanningCriterion.routeOrder[index])
                },
                onTravel: { route.travel(to: $0, animated: $1, reduceMotion: reduceMotion) })
                .ignoresSafeArea(edges: .bottom)
            VStack(spacing: 0) {
                LinearGradient(colors: [Color(cgColor: DateRouteScene.navy), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 180)
                Spacer()
                LinearGradient(colors: [.clear, Color(cgColor: DateRouteScene.navy)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    if let onClose {
                        Button(action: onClose) {
                            // A thin glyph inside a transparent frame is only tappable on the
                            // glyph's own pixels. Give the button a real, generous hit area.
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 48, height: 48)
                                .background(Color(cgColor: DateRouteScene.navy).opacity(0.72), in: Circle())
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("Planung schließen")
                    }
                    Spacer()
                    Button(action: onGenerate) {
                        Group {
                            if isPreparing { ProgressView().tint(PBTheme.textPrimary) }
                            else { Image(systemName: "checkmark").font(.system(size: 20, weight: .medium)) }
                        }
                        .frame(width: 48, height: 48)
                        .foregroundStyle(PBTheme.textPrimary)
                        .background(PBTheme.surface, in: Circle())
                    }
                    .disabled(isPreparing)
                    .accessibilityLabel("Mit diesen Einstellungen Ideen generieren")
                    .accessibilityHint("Du musst nicht jede Station öffnen. Voreinstellungen werden übernommen.")
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                VStack(spacing: 9) {
                    Text(criteria.planningMode == .group ? "EUER WEG ZUM TREFFEN" : "EUER WEG ZUM DATE").font(.system(size: 10, weight: .medium)).tracking(3)
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                    Text(title).font(.system(size: 34, weight: .ultraLight))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("Alles ist voreingestellt. Macht es zu eurem.")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(PBTheme.textOnDarkSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .allowsHitTesting(false)
                Spacer()
                controls.padding(.horizontal, 22).padding(.bottom, 14)
            }
            // The route controls share the 3D canvas right to the lower system edge. Their
            // own small inset keeps them clear of the Home indicator without a blue gap below.
            .ignoresSafeArea(edges: .bottom)
        }
        .foregroundStyle(PBTheme.textOnDark)
        .buttonStyle(.plain)
        .onAppear { route.update(criteria: criteria); isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: criteria) { _, value in route.update(criteria: value) }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                arrow("chevron.left", step: -1)
                Button { onSelect(route.selectedCriterion) } label: {
                    VStack(spacing: 6) {
                        Text(String(format: "%02d / %02d", route.selectedIndex + 1, PlanningCriterion.routeOrder.count))
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(PBTheme.textOnDarkSecondary)
                        HStack(spacing: 8) {
                            Text(route.selectedCriterion.title(in: criteria.planningMode)).lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: "pencil").font(.system(size: 11, weight: .light))
                        }.font(.system(size: 14, weight: .light))
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Color(cgColor: DateRouteScene.navy).opacity(0.95), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.23), lineWidth: 0.7) }
                }
                .accessibilityLabel("\(route.selectedCriterion.title(in: criteria.planningMode)): \(route.selectedCriterion.value(in: criteria))")
                .accessibilityHint("Einstellung bearbeiten")
                arrow("chevron.right", step: 1)
            }
            Text(route.selectedIndex == PlanningCriterion.routeOrder.count - 1
                 ? "Bereit? Mit dem Haken oben startet eure Idee."
                 : "Kreis antippen · Hochwischen zum nächsten Schritt")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(PBTheme.textOnDarkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func arrow(_ symbol: String, step: Int) -> some View {
        let target = route.selectedIndex + step
        return Button {
            route.travel(to: Float(target), animated: true, reduceMotion: reduceMotion)
        } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .light))
                .frame(width: 44, height: 48)
                .background(Color(cgColor: DateRouteScene.navy).opacity(0.8), in: Circle())
        }
        .disabled(!PlanningCriterion.routeOrder.indices.contains(target))
        .opacity(PlanningCriterion.routeOrder.indices.contains(target) ? 1 : 0.3)
        .accessibilityLabel(step < 0 ? "Vorherige Einstellung" : "Nächste Einstellung")
    }
}
