import SwiftUI

/// Les jetons du design, décrits dans docs/design.md. Aucune couleur, taille ni rayon en dur ailleurs.
nonisolated enum Theme {
    // MARK: couleurs

    static let fond = Color(hex: 0x050506)
    /// Le fond d'une carte, d'un menu, de la palette.
    static let carte = Color(hex: 0x0C0C0E)
    /// Une surface posée sur une carte : ligne survolée, champ, bulle d'aide.
    static let releve = Color(hex: 0x17171A)
    static let texte = Color(hex: 0xF5F5F4)
    static let secondaire = Color(hex: 0xA1A1A6)
    static let tertiaire = Color(hex: 0x66666C)
    /// Le blanc d'action : onglet choisi, lien, série principale.
    static let accent = texte
    // états, toujours avec un libellé
    static let succes = Color(hex: 0x4ADE80)
    static let ambre = Color(hex: 0xFBBF24)
    static let danger = Color(hex: 0xF87171)
    // catégories : séries d'un graphique, plateformes, business, dans cet ordre
    static let orange = Color(hex: 0xD95926)
    static let bleu = Color(hex: 0x3987E5)
    static let aqua = Color(hex: 0x199E70)
    static let violet = Color(hex: 0x9085E9)

    /// Le jeton `teinte` d'un business, gardé en base sous son ancien nom.
    static func teinte(_ cle: String) -> Color {
        switch cle {
        case "ciel": bleu
        case "lilas": violet
        case "ambre": orange
        default: aqua
        }
    }

    /// Les teintes proposées dans Réglages : clé en base, nom affiché.
    static let teintes = [(cle: "menthe", nom: "Aqua"), (cle: "ciel", nom: "Bleu"), (cle: "lilas", nom: "Violet"), (cle: "ambre", nom: "Orange")]

    /// Fond d'une pastille de la couleur `c` ; le gris neutre est un blanc léger.
    static func doux(_ c: Color) -> Color { c == secondaire ? .white.opacity(0.07) : c.opacity(0.14) }

    /// Blancs translucides des cartes et des lignes.
    enum Blanc {
        /// Le filet d'une carte, d'un séparateur.
        static let bord = 0.07
        /// Le filet d'une pilule, d'un champ, d'une carte survolée.
        static let bordFort = 0.13
        static let bloc = 0.04
        static let ligne = 0.03
        static let survol = 0.05
        static let pilule = 0.06
        static let actif = 0.1
        static let selection = 0.14
        static let fantome = 0.09
        static let barre = 0.85
        /// La pastille de légende d'une série en fantôme, plus visible que ses barres.
        static let repere = 0.22
        /// Grille d'un graphique, filet séparateur.
        static let grille = 0.06
        /// Une série secondaire d'un graphique (MRR brut), un trait neutre de sparkline.
        static let serie = 0.4
        static let trait = 0.5
        /// Ombre sous une pilule choisie.
        static let ombre = 0.35
        /// Le halo d'un chiffre héros ou du point au bout d'une courbe.
        static let halo = 0.16
    }

    /// La lueur blanche qui tombe du haut de la fenêtre.
    static let lueur = EllipticalGradient(colors: [.white.opacity(0.075), .white.opacity(0.02), .clear], startRadiusFraction: 0, endRadiusFraction: 0.5)

    /// Le voile sous la palette ⌘K.
    static let voile = Color.black.opacity(0.55)

    /// Le trait d'une courbe.
    static let trait = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    /// Le repère vertical sous la souris dans un graphique.
    static let viseur = StrokeStyle(lineWidth: 1, dash: [3, 3])

    // MARK: formes

    enum Rayon {
        static let panneau: CGFloat = 20
        static let carte: CGFloat = 18
        static let bloc: CGFloat = 14
        static let bouton: CGFloat = 12
        static let tache: CGFloat = 11
        static let ligne: CGFloat = 10
        static let avatar: CGFloat = 8
        static let barre: CGFloat = 4
    }

    enum Espace {
        static let xs: CGFloat = 2
        static let s: CGFloat = 4
        static let m: CGFloat = 8
        static let l: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
        static let panneau: CGFloat = 20
        static let page: CGFloat = 28
    }

    enum Taille {
        /// La barre du haut ; la place laissée aux boutons de la fenêtre.
        static let barreHaut: CGFloat = 52
        static let feux: CGFloat = 78
        /// Une ligne de la palette ou de la barre de menus.
        static let itemNav: CGFloat = 36
        static let avatar: CGFloat = 32
        /// L'avatar du business dans la barre du haut.
        static let avatarMini: CGFloat = 26
        // logos des plateformes
        static let logoMini: CGFloat = 12
        static let logo: CGFloat = 16
        static let logoGrand: CGFloat = 20
        static let bouton: CGFloat = 34
        static let segment: CGFloat = 30
        static let ligneFil: CGFloat = 30
        static let ligneVideo: CGFloat = 34
        static let ligneTache: CGFloat = 38
        static let caseTache: CGFloat = 20
        static let sparkline = CGSize(width: 76, height: 24)
        static let barresHeure: CGFloat = 128
        static let graphique: CGFloat = 128
        static let graphiqueHaut: CGFloat = 170
        static let graphiqueHeros: CGFloat = 210
        /// Aire d'un point de courbe (`symbolSize`).
        static let pointCourbe: CGFloat = 18
        static let icone: CGFloat = 17
        static let point: CGFloat = 7
        static let pointMini: CGFloat = 6
        static let fenetre = CGSize(width: 1320, height: 920)
        static let fenetreMin = CGSize(width: 1080, height: 720)
        static let palette: CGFloat = 600
        static let champPalette: CGFloat = 54
        static let listePalette: CGFloat = 380
        static let barreMenus: CGFloat = 340
        /// La bulle des sources sous la barre du haut.
        static let bulle: CGFloat = 300
        /// La hauteur de la lueur du haut de la fenêtre.
        static let lueur: CGFloat = 680
        static let reglages = CGSize(width: 600, height: 640)
        /// Le rond et l'horizon de la marque, devant « Cockpit ».
        static let marque: CGFloat = 20
        // colonnes de l'Accueil
        static let panneauReseau: CGFloat = 248
        static let panneauPlan: CGFloat = 280
        /// Un panneau de l'Accueil replié.
        static let rail: CGFloat = 52
        static let radar: CGFloat = 156
        /// L'épaisseur d'une jauge de progression.
        static let jauge: CGFloat = 6
        // l'écran SAV
        /// La hauteur des bulles d'un fil ouvert.
        static let conversation: CGFloat = 460
        /// La hauteur du champ de réponse.
        static let reponse: CGFloat = 88
        // le widget du bureau
        static let marqueWidget: CGFloat = 13
        static let courbeWidget: CGFloat = 40
        static let sparklineWidget: CGFloat = 16
    }

    // MARK: texte

    enum Police {
        static let titre = Font.system(size: 30, weight: .semibold)
        static let h2 = Font.system(size: 15, weight: .semibold)
        static let kpi = Font.system(size: 30, weight: .semibold)
        static let grand = Font.system(size: 22, weight: .semibold)
        /// Le chiffre héros de l'Accueil.
        static let heros = Font.system(size: 76, weight: .semibold)
        /// « Cockpit » au centre de la barre du haut, à côté de la marque.
        static let marque = Font.system(size: 18, weight: .semibold)
        static let corps = Font.system(size: 13.5, weight: .regular)
        static let corpsGras = Font.system(size: 13.5, weight: .semibold)
        static let ligne = Font.system(size: 13.5, weight: .medium)
        static let label = Font.system(size: 12.5, weight: .semibold)
        static let petit = Font.system(size: 12, weight: .regular)
        static let mini = Font.system(size: 11.5, weight: .regular)
        static let miniGras = Font.system(size: 11.5, weight: .semibold)
        /// Le petit titre en capitales d'une carte, façon terminal de marché.
        static let surtitre = Font.system(size: 11, weight: .medium, design: .monospaced)
        static let tag = Font.system(size: 10.5, weight: .medium, design: .monospaced)
        // le widget du bureau
        static let widgetHeros = Font.system(size: 34, weight: .semibold)
        static let widgetHerosGrand = Font.system(size: 44, weight: .semibold)
        static let widgetKpi = Font.system(size: 19, weight: .semibold)
        static let axe = Font.system(size: 10.5, weight: .regular, design: .monospaced)
        // symboles SF
        static let coche = Font.system(size: 9, weight: .heavy)
        static let fleche = Font.system(size: 10, weight: .bold)
        static let symbole = Font.system(size: 13, weight: .semibold)
        static let icone = Font.system(size: 14, weight: .semibold)
        static let symboleGrand = Font.system(size: 15, weight: .semibold)
    }

    // MARK: mouvement

    /// Les ressorts de l'app, un par geste ; Reduce Motion les coupe tous dans `Racine`.
    enum Anim {
        /// Écran, business, pilules, palette.
        static let navigation = Animation.spring(duration: 0.45, bounce: 0.18)
        /// Un chiffre qui roule.
        static let chiffre = Animation.spring(duration: 0.6, bounce: 0.1)
        /// Survol, appui, ligne choisie.
        static let survol = Animation.spring(duration: 0.25, bounce: 0.3)
        /// Un bloc qui entre, une barre qui pousse.
        static let entree = Animation.spring(duration: 0.55, bounce: 0.15)
        /// Une courbe qui se trace, un graphique qui se dévoile.
        static let trace = Animation.easeOut(duration: 0.9)
        /// Écart entre deux blocs qui entrent l'un après l'autre (s).
        static let decalage = 0.05
        /// Écart entre deux barres d'heure qui poussent (s).
        static let decalageBarre = 0.012
        /// Au-delà, les blocs entrent ensemble.
        static let rangMax = 8
        static let appui: CGFloat = 0.96
        static let appuiCarte: CGFloat = 0.98
        static let survolEchelle: CGFloat = 1.012
        static let survolLumiere = 0.025
        /// Le glissement d'un écran ou d'un bloc qui entre.
        static let glisse: CGFloat = 14
        static let flou: CGFloat = 8
        static let reduit: CGFloat = 0.98
    }
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
