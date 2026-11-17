import Foundation

/// Nombres, argent, dates et durées tels que l'UI les écrit, au format français (`48 200`, `7,10 €`, `−4 %`).
enum Format {
    static let locale = Locale(identifier: "fr_FR")
    /// Ce qu'on affiche tant qu'une source n'a rien écrit.
    static let vide = "…"
    /// Le vrai signe moins, pas le trait d'union.
    static let moins = "\u{2212}"

    static func entier(_ v: Double) -> String {
        v.rounded().formatted(.number.locale(locale).precision(.fractionLength(0)))
    }

    static func entier(_ v: Int) -> String { entier(Double(v)) }

    static func decimal(_ v: Double, _ decimales: Int) -> String {
        v.formatted(.number.locale(locale).precision(.fractionLength(decimales)))
    }

    /// `6 420`, `25,4 k`, `48 k`, `337 k`, `1,2 M` : une décimale sous 100 k, pour qu'un axe serré ne répète pas `26 k`.
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        let s = v < 0 ? moins : ""
        let auPlusUne = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(0...1))
        if a < 10_000 { return s + entier(a) }
        if a < 100_000 { return s + (a / 1000).formatted(auPlusUne) + " k" }
        if a < 1_000_000 { return s + entier(a / 1000) + " k" }
        return s + (a / 1_000_000).formatted(auPlusUne) + " M"
    }

    /// `+412`, `−96`, `+0`.
    static func delta(_ v: Double, compacte: Bool = false) -> String {
        let corps = compacte ? compact(abs(v)) : entier(abs(v))
        return (v < 0 ? moins : "+") + corps
    }

    /// Un écart en unités, `= 0` s'il est nul.
    static func unites(_ ecart: Double?) -> String? { ecart.map { $0 == 0 ? "= 0" : delta($0) } }

    /// `3 essais`, `1 achat`, `0 rond` : le pluriel commence à 2.
    static func nombre(_ v: Double?, _ mot: String) -> String? {
        v.map { entier($0) + " " + mot + (abs($0) < 2 ? "" : "s") }
    }

    /// `0,99 %` pour 0,0099.
    static func pourcent(_ ratio: Double, decimales: Int = 0) -> String {
        decimal(ratio * 100, decimales) + " %"
    }

    /// Variation relative : `+9 %`, `−4 %` ; nil si la référence est nulle.
    static func variation(_ actuel: Double, _ avant: Double) -> String? {
        guard avant != 0 else { return nil }
        let r = ((actuel - avant) / avant * 100).rounded()
        return (r < 0 ? moins : "+") + entier(abs(r)) + " %"
    }

    /// Variation relative entre deux relevés facultatifs : `= 0` si les deux sont nuls, nil s'il en manque un.
    static func evolution(_ actuel: Double?, _ avant: Double?) -> String? {
        guard let actuel, let avant else { return nil }
        return variation(actuel, avant) ?? (actuel == 0 ? "= 0" : nil)
    }

    /// Écart brut entre deux relevés facultatifs ; nil s'il en manque un.
    static func ecart(_ actuel: Double?, _ avant: Double?) -> Double? {
        guard let actuel, let avant else { return nil }
        return actuel - avant
    }

    /// Un écart de taux en points : `+1,2 pt` ; nil s'il manque un taux.
    static func points(_ actuel: Double?, _ avant: Double?) -> String? {
        ecart(actuel, avant).map { e in
            let p = (e * 1000).rounded() / 10
            return p == 0 ? "= 0 pt" : (p < 0 ? moins : "+") + decimal(abs(p), 1) + " pt"
        }
    }

    /// Un montant signé : `+97 €`, `−12 €`.
    static func signe(_ v: Double, _ format: (Double) -> String) -> String {
        (v < 0 ? moins : "+") + format(abs(v))
    }

    /// `7,10 €`, `1 240 €`.
    static func euros(_ v: Double) -> String { argent(v, "€") }


    private static func argent(_ v: Double, _ devise: String) -> String {
        (abs(v) >= 100 ? entier(v) : decimal(v, 2)) + " " + devise
    }

    /// `12 400`, `1,2 M`.
    /// `dont 4,10 € de voix`.
    static func dontVoix(_ v: Double) -> String { "dont \(euros(v)) de voix" }

    /// `152e`, `1er`.
    static func rang(_ p: Int) -> String { p == 1 ? "1er" : "\(p)e" }

    // MARK: dates

    private static func formateur(_ modele: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = Jour.fuseau
        f.dateFormat = modele
        return f
    }

    private static let fHeure = formateur("HH:mm")
    private static let fJourCourt = formateur("d MMM")
    private static let fDateLongue = formateur("EEEE d MMMM")
    private static let fJourHeure = formateur("d MMM, HH:mm")
    private static let fJourSemaine = formateur("EEEE")
    private static let fMoisAnnee = formateur("MMMM yyyy")

    /// `14:52`
    static func heure(_ d: Date) -> String { fHeure.string(from: d) }

    /// `17 nov.`
    static func jourCourt(_ d: Date) -> String { fJourCourt.string(from: d) }

    /// `mars 2027`.
    static func moisAnnee(_ d: Date) -> String { fMoisAnnee.string(from: d) }

    /// `17 nov.` depuis une clé `yyyy-MM-dd`.
    static func jourCourt(cle: String) -> String { Jour.date(cle).map(jourCourt) ?? cle }

    /// `12 nov., 14:52`
    static func jourHeure(_ d: Date) -> String { fJourHeure.string(from: d) }

    /// `jeudi`
    static func jourSemaine(_ d: Date) -> String { fJourSemaine.string(from: d) }

    /// `Jeudi 12 novembre`
    static func dateLongue(_ d: Date) -> String {
        let s = fDateLongue.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// `à l'instant`, `il y a 3 min`, `il y a 2 h`, `il y a 4 j`.
    static func ilYa(_ d: Date, maintenant: Date = .now) -> String {
        let s = max(0, maintenant.timeIntervalSince(d))
        if s < 60 { return "à l'instant" }
        if s < 3600 { return "il y a \(Int(s / 60)) min" }
        if s < 86_400 { return "il y a \(Int(s / 3600)) h" }
        return "il y a \(Int(s / 86_400)) j"
    }

    /// Âge d'une vidéo en jours calendaires de Paris : `J+0` à `J+6`, puis `19 j`.
    static func age(_ d: Date, maintenant: Date = .now) -> String {
        let debut = Jour.calendrier.startOfDay(for: d)
        let fin = Jour.calendrier.startOfDay(for: maintenant)
        let n = max(0, Jour.calendrier.dateComponents([.day], from: debut, to: fin).day ?? 0)
        return n < 7 ? "J+\(n)" : "\(n) j"
    }

    /// Cadence d'une source : `15 min`, `1 h`, `3 h`.
    static func cadence(_ s: TimeInterval) -> String {
        s < 3600 ? entier(s / 60) + " min" : entier(s / 3600) + " h"
    }

    /// Une durée courte : `0,8 s`, `12 s`.
    static func duree(_ s: TimeInterval) -> String {
        s < 10 ? decimal(s, 1) + " s" : entier(s) + " s"
    }

    /// Un temps cumulé : `45 s`, `12 min`, `3,4 h`, `164 h`.
    static func cumul(_ s: TimeInterval) -> String {
        s < 60 ? duree(s) : s < 3600 ? entier(s / 60) + " min" : s < 36_000 ? decimal(s / 3600, 1) + " h" : entier(s / 3600) + " h"
    }

    /// Durée d'un passage, à la seconde comme les horodatages de `collecte` : `< 1 s`, `12 s`.
    static func passage(_ s: TimeInterval) -> String {
        s < 1 ? "< 1 s" : entier(s) + " s"
    }
}
