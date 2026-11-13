import Foundation
import SwiftUI

/// The visual foundation for Mite's "Midnight Ink" identity. Controls are tonal layers of the
/// canvas rather than bright white objects placed on top of it.
enum PBTheme {
    // MARK: - Colour

    static let midnight = Color(red: 0.035, green: 0.125, blue: 0.210)
    static let midnightRaised = Color(red: 0.055, green: 0.180, blue: 0.285)
    static let midnightSoft = Color(red: 0.085, green: 0.235, blue: 0.355)
    static let accent = Color(red: 0.255, green: 0.470, blue: 0.710)
    static let accentMuted = Color(red: 0.255, green: 0.470, blue: 0.710).opacity(0.20)
    static let controlSurface = Color(red: 0.070, green: 0.185, blue: 0.285)
    static let controlSurfaceRaised = Color(red: 0.095, green: 0.235, blue: 0.355)
    static let controlBorder = Color.white.opacity(0.15)
    static let controlSelected = Color(red: 0.165, green: 0.360, blue: 0.610)
    /// Translucent dark layers for routes, maps and other content that should feel part of the
    /// Midnight Ink canvas rather than like an ivory settings form placed on top of it.
    static let routeSurface = Color.white.opacity(0.075)
    static let routeSurfaceRaised = Color.white.opacity(0.115)
    static let routeLine = Color.white.opacity(0.34)

    static let background = midnight
    static let surface = Color(red: 0.965, green: 0.940, blue: 0.895)
    static let surfaceMuted = Color(red: 0.910, green: 0.880, blue: 0.825)
    static let surfaceOnDark = Color(red: 0.965, green: 0.940, blue: 0.895).opacity(0.96)
    static let textPrimary = Color(red: 0.055, green: 0.075, blue: 0.100)
    static let textSecondary = Color(red: 0.300, green: 0.335, blue: 0.375)
    static let textOnDark = Color(red: 0.985, green: 0.965, blue: 0.925)
    static let textOnDarkSecondary = Color(red: 0.820, green: 0.855, blue: 0.880)

    static let success = Color(red: 0.290, green: 0.610, blue: 0.490)
    static let warning = Color(red: 0.790, green: 0.560, blue: 0.220)
    static let destructive = Color(red: 0.760, green: 0.245, blue: 0.255)

    // MARK: - Type

    enum Typography {
        /// Midnight Ink uses SF Pro's default display cut: quieter and more editorial than the
        /// rounded system face, while still scaling naturally with every iOS text setting.
        static let greeting = Font.system(size: 29, weight: .regular, design: .default)
        static let display = Font.system(size: 32, weight: .semibold, design: .default)
        static let title = Font.system(.title2, design: .default, weight: .semibold)
        static let headline = Font.system(.headline, design: .default, weight: .semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let micro = Font.system(size: 11, weight: .medium, design: .default)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 44
    }

    enum Radius {
        static let small: CGFloat = 14
        static let card: CGFloat = 22
        static let hero: CGFloat = 28
        static let pill: CGFloat = 100
    }

    enum Shadow {
        static let card = Color.black.opacity(0.16)
        static let dock = Color.black.opacity(0.30)
    }
}

/// Mite currently ships with German product copy only. Foundation formatters do not inherit
/// SwiftUI's environment locale when they are evaluated into strings, so calendar and date
/// output stay explicit even when the test device itself uses English.
enum PBLocalization {
    static let germanLocale = Locale(identifier: "de_DE")

    static var germanCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = germanLocale
        calendar.firstWeekday = 2
        return calendar
    }

    static var shortWeekdaySymbolsStartingMonday: [String] {
        ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    }
}

extension Date {
    var miteTimeText: String {
        formatted(.dateTime.hour().minute().locale(PBLocalization.germanLocale))
    }

    var miteAbbreviatedDateTimeText: String {
        formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(PBLocalization.germanLocale))
    }

    var miteCompleteDateTimeText: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute().locale(PBLocalization.germanLocale))
    }

    var miteLongDateTimeText: String {
        formatted(.dateTime.day().month(.wide).year().hour().minute().locale(PBLocalization.germanLocale))
    }

    var miteCompleteDateText: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(PBLocalization.germanLocale))
    }

    var miteWeekdayText: String {
        formatted(.dateTime.weekday(.wide).locale(PBLocalization.germanLocale))
    }

    var miteAbbreviatedDayMonthText: String {
        formatted(.dateTime.day().month(.abbreviated).locale(PBLocalization.germanLocale))
    }

    var miteLongDayMonthText: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide).locale(PBLocalization.germanLocale))
    }
}
