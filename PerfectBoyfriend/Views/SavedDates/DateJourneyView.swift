import SwiftUI
import MapKit

struct DateJourneyView: View {
    let scope: DatePlanningScope
    let savedDate: SavedDate
    @ObservedObject var savedDateService: SavedDateService
    @State private var changingOrder: Int?
    @State private var errorMessage: String?

    private var current: SavedDate { savedDateService.savedDates.first { $0.id == savedDate.id } ?? savedDate }
    private var stops: [DateRouteStop] { DateSchedule.stops(current.stations, startingAt: current.scheduledAt.dateValue()) }
    private var completed: Set<Int> { Set(current.completedStationOrders ?? []) }

    var body: some View {
        PBScreenContainer {
            TimelineView(.periodic(from: .now, by: 30)) { clock in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Euer Abend. Schritt für Schritt.")
                                .font(PBTheme.Typography.display)
                            Text(current.title).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                            Label("\(completed.count) von \(stops.count) Stationen erlebt", systemImage: "checkmark.circle")
                                .font(PBTheme.Typography.caption)
                        }
                        if current.status == .cancelled {
                            Text("Dieses Date wurde abgesagt.").foregroundStyle(PBTheme.textOnDarkSecondary)
                        } else if current.scheduledAt.dateValue() > clock.date {
                            Text("Euer Plan steht. Ab \(current.scheduledAt.dateValue().miteAbbreviatedDateTimeText) könnt ihr Stationen gemeinsam abhaken.")
                                .font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
                        }
                        ForEach(stops) { stop in
                            stopCard(stop, now: clock.date)
                        }
                        if current.canRate {
                            NavigationLink {
                                RateDateView(scope: scope, savedDate: current, savedDateService: savedDateService)
                            } label: {
                                Label("Wie war euer Date?", systemImage: "star")
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(PBTheme.surface, in: Capsule())
                                    .foregroundStyle(PBTheme.textPrimary)
                            }.buttonStyle(.plain)
                        }
                        ShareLink(item: DateSchedule.shareText(title: current.title, stations: current.stations, startingAt: current.scheduledAt.dateValue())) {
                            Label("Ablauf teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .tint(PBTheme.textOnDark)
                        Text("Euer Fortschritt wird mit der anderen Person geteilt. Das Teilen des Ablaufs gibt nur den Plan weiter, keinen Live-Standort.")
                            .font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                    }.padding(20)
                }
            }
        }
        .foregroundStyle(PBTheme.textOnDark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert("Konnte nicht aktualisiert werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func stopCard(_ stop: DateRouteStop, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DateStationVisual(station: stop.station).frame(height: 175)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            HStack {
                Text(stop.startsAt, format: .dateTime.hour().minute()).monospacedDigit()
                Text("· \(stop.station.estimatedDurationMinutes) Min")
                Spacer()
                if completed.contains(stop.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(PBTheme.success) }
            }.font(PBTheme.Typography.caption)
            Text(stop.station.title).font(PBTheme.Typography.title)
            Text(stop.station.description).font(PBTheme.Typography.body).foregroundStyle(PBTheme.textOnDarkSecondary)
            if let transfer = stop.station.arrivalTransfer {
                Label("Davor ca. \(transfer.minutes) Min · \(transfer.transport)", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(PBTheme.Typography.caption)
            }
            if let place = stop.station.resolvedPlace {
                Text(place.address).font(PBTheme.Typography.caption).foregroundStyle(PBTheme.textOnDarkSecondary)
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)))
                    item.name = place.name
                    item.openInMaps()
                } label: {
                    Label("Navigation & Öffnungszeiten", systemImage: "map").frame(minHeight: 44)
                }.tint(PBTheme.textOnDark)
            }
            if current.status == .upcoming {
                Button {
                    Task { await toggle(stop) }
                } label: {
                    Label(changingOrder == stop.id ? "Wird gespeichert …" : completed.contains(stop.id) ? "Als offen markieren" : "Station erlebt",
                          systemImage: completed.contains(stop.id) ? "arrow.uturn.backward" : "checkmark")
                        .font(PBTheme.Typography.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(PBTheme.routeSurfaceRaised, in: Capsule())
                }.buttonStyle(.plain)
                    .disabled(changingOrder != nil || current.scheduledAt.dateValue() > now)
            }
            if let image = stop.station.licensedImage {
                LicensedImageCredit(image: image, foregroundColor: PBTheme.textOnDarkSecondary)
            }
        }.padding(14)
            .background(PBTheme.routeSurface, in: RoundedRectangle(cornerRadius: PBTheme.Radius.hero))
    }

    private func toggle(_ stop: DateRouteStop) async {
        guard let id = current.id, changingOrder == nil else { return }
        changingOrder = stop.id
        defer { changingOrder = nil }
        do {
            try await savedDateService.setStationCompleted(scope: scope, dateId: id, stationOrder: stop.id, completed: !completed.contains(stop.id))
        } catch { errorMessage = error.localizedDescription }
    }
}
