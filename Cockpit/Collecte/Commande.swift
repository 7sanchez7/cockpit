import Foundation

/// Lance un programme local (gcloud, security, yt-dlp) sans bloquer l'interface.
enum Commande {
    /// Rend la sortie standard ; lève `SourceErreur.commande` avec la sortie d'erreur si le code n'est pas 0.
    nonisolated static func lancer(_ chemin: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { suite in
            DispatchQueue.global().async {
                do {
                    let erreurs = FileManager.default.temporaryDirectory.appending(path: "cockpit-\(UUID().uuidString).err")
                    FileManager.default.createFile(atPath: erreurs.path, contents: nil)
                    defer { try? FileManager.default.removeItem(at: erreurs) }
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: chemin)
                    p.arguments = arguments
                    let sortie = Pipe()
                    p.standardOutput = sortie
                    p.standardError = try FileHandle(forWritingTo: erreurs)
                    try p.run()
                    let donnees = sortie.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    guard p.terminationStatus == 0 else {
                        let message = (try? String(contentsOf: erreurs, encoding: .utf8)) ?? ""
                        let nom = URL(fileURLWithPath: chemin).lastPathComponent
                        throw SourceErreur.commande("\(nom) a échoué (\(p.terminationStatus)) : \(message.prefix(300))")
                    }
                    suite.resume(returning: donnees)
                } catch {
                    suite.resume(throwing: error)
                }
            }
        }
    }

    /// Une ligne de commande dans un zsh de connexion, pour avoir le PATH de Homebrew depuis une app.
    nonisolated static func shell(_ ligne: String) async throws -> Data {
        try await lancer("/bin/zsh", ["-lc", ligne])
    }
}
