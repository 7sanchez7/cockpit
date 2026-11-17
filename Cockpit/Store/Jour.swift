import Foundation

/// Jours et heures à l'heure de Paris (`yyyy-MM-dd`, 0 à 23), instants en ISO 8601 UTC.
enum Jour {
    static let fuseau = TimeZone(identifier: "Europe/Paris")!

    static let calendrier: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = fuseau
        c.locale = Locale(identifier: "fr_FR")
        c.firstWeekday = 2
        return c
    }()

    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendrier
        f.timeZone = fuseau
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var aujourdhui: String { cle(.now) }

    static func cle(_ date: Date) -> String { format.string(from: date) }

    /// Minuit à Paris ce jour-là.
    static func date(_ cle: String) -> Date? { format.date(from: cle) }

    static func decale(_ cle: String, jours: Int) -> String {
        guard let d = date(cle), let n = calendrier.date(byAdding: .day, value: jours, to: d) else { return cle }
        return Jour.cle(n)
    }

    static func heure(_ date: Date) -> Int { calendrier.component(.hour, from: date) }

    /// Les `n` derniers jours, du plus ancien à `fin` inclus.
    static func derniers(_ n: Int, jusqua fin: String = aujourdhui) -> [String] {
        (0..<n).reversed().map { decale(fin, jours: -$0) }
    }
}

extension Date {
    private static let isoSimple: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let isoFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `2026-11-13T14:05:00Z`
    var iso: String { Date.isoSimple.string(from: self) }

    /// Lit l'ISO 8601 avec ou sans fractions de seconde.
    init?(iso: String) {
        guard let d = Date.isoSimple.date(from: iso) ?? Date.isoFractions.date(from: iso) else { return nil }
        self = d
    }
}
