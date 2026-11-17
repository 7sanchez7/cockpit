import Foundation

extension Lectures {
    /// Le résumé du widget : les chiffres d'aujourd'hui de l'Accueil, comparés et annotés comme l'Accueil.
    func resumeWidget() -> ResumeWidget {
        let f = Fenetre(periode: .jour, maintenant: maintenant)
        let n = Periode.mois.rawValue
        func euros(_ v: Double?) -> String? { v.map { Format.euros(Metrique.enEuros($0)) } }
        func kpi(_ libelle: String, _ c: Chiffres, delta: (Double?) -> String?, note: String?) -> ResumeWidget.Kpi {
            let ecart = Format.ecart(c.valeur, c.avant)
            return ResumeWidget.Kpi(libelle: libelle, valeur: c.valeur.map(Format.entier) ?? Format.vide,
                                    delta: delta(ecart), ecart: ecart, note: note, serie: c.serie)
        }

        let essais = f.mesure(self, Metrique.essais, j7: Metrique.essaisJ7)
        let installs = f.mesure(self, Metrique.installs, j7: Metrique.installsJ7)
        let actifs = f.mesure(self, Metrique.actifs, j7: Metrique.actifsJ7)
        let vues = f.mesure(self, Metrique.vuesTikTok, j7: Metrique.vuesTikTokJ7)
        let conversion = installs.valeur.flatMap { $0 > 0 ? Format.pourcent((essais.valeur ?? 0) / $0) : nil }
        let publiees = publications(f.n, jusqua: f.fin).reduce(0, +)
        let detail = [Format.nombre(essais.valeur, "essai"), Format.nombre(f.mesure(self, Metrique.achats).valeur, "achat")]
            .compactMap { $0 }.joined(separator: ", ")

        return ResumeWidget(
            maj: derniersPassages().values.map(\.fin).max().map {
                Calendar.current.isDate($0, inSameDayAs: maintenant) ? Format.heure($0) : Format.jourHeure($0)
            },
            revenu: euros(valeur(Metrique.revenu, jour: f.fin)) ?? Format.vide,
            hier: "hier " + (euros(valeur(Metrique.revenu, jour: Jour.decale(f.fin, jours: -1))) ?? Format.vide),
            detail: detail.isEmpty ? Format.vide : detail,
            cumul: revenuCumule(n, jusqua: f.fin).map(\.euros),
            jours: n,
            kpis: [
                kpi("Abonnés", f.mesure(self, Metrique.abonnes, cumul: .dernier), delta: Format.unites,
                    note: euros(valeur(Metrique.mrrBrut, jour: f.fin)).map { "MRR " + $0 }),
                kpi("Essais", essais, delta: Format.unites,
                    note: valeur(Metrique.essaisActifs, jour: f.fin).map { Format.entier($0) + " en cours" }),
                kpi("Installs", installs, delta: { _ in Format.evolution(installs.valeur, installs.avant) },
                    note: conversion.map { $0 + " en essai" }),
                kpi("Actifs", actifs, delta: { _ in Format.evolution(actifs.valeur, actifs.avant) },
                    note: Format.nombre(f.mesure(self, Metrique.ronds, j7: Metrique.rondsJ7).valeur, "rond")),
                kpi("Vues TikTok", vues, delta: { _ in Format.evolution(vues.valeur, vues.avant) },
                    note: Format.nombre(Double(publiees), "vidéo").map { $0 + (publiees < 2 ? " publiée" : " publiées") }),
            ],
            aTraiter: nbATraiter())
    }
}
