import Foundation

/// Where Pi lives and whether it will load this project's resources.
enum PiEnvironment {
    static func findProjectDirectory() -> URL {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["PI_PROJECT_PATH"].map(URL.init(fileURLWithPath:)),
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        ].compactMap { $0 }

        if let match = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent(".pi/settings.json").path)
        }) {
            return match
        }
        return candidates.first ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }

    /// The `pi` launcher. Finder-launched apps get a minimal PATH, so we look in
    /// the usual npm/homebrew places explicitly.
    static func findPiExecutable() -> String? {
        let fileManager = FileManager.default
        if let configured = ProcessInfo.processInfo.environment["PI_PATH"],
           fileManager.isExecutableFile(atPath: configured) {
            return configured
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/.npm-global/bin/pi",
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "\(home)/.local/bin/pi"
        ]
        if let versions = try? fileManager.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            candidates += versions.sorted(by: >).map { "\(home)/.nvm/versions/node/\($0)/bin/pi" }
        }
        for entry in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(entry)/pi")
        }
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    /// PATH for the Pi process: pi-agents spawns delegated `pi` children by
    /// name, and pi's own launcher needs `node`, so both directories must be
    /// on PATH even when the app was opened from Finder.
    static func processEnvironment(piExecutable: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let fileManager = FileManager.default
        let resolvedPi = URL(fileURLWithPath: piExecutable).resolvingSymlinksInPath().deletingLastPathComponent().path
        let piDir = URL(fileURLWithPath: piExecutable).deletingLastPathComponent().path
        var entries = [piDir, resolvedPi, "/opt/homebrew/bin", "/usr/local/bin"]
        if let versions = try? fileManager.contentsOfDirectory(atPath: "\(fileManager.homeDirectoryForCurrentUser.path)/.nvm/versions/node") {
            entries += versions.sorted(by: >).map { "\(fileManager.homeDirectoryForCurrentUser.path)/.nvm/versions/node/\($0)/bin" }
        }
        let existing = (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = (entries + existing).filter { seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    // MARK: Project trust

    private static var trustFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/trust.json")
    }

    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Delegated agents are spawned by pi-agents without `--approve`, so the
    /// project must be trusted persistently in `~/.pi/agent/trust.json` or the
    /// children will not load project skills, profiles, or the gate tool.
    static func isProjectTrusted(_ projectDirectory: URL) -> Bool {
        guard let data = try? Data(contentsOf: trustFile),
              let decisions = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        var dir = canonical(projectDirectory)
        while true {
            if let decision = decisions[dir] as? Bool { return decision }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { return false }
            dir = parent
        }
    }

    /// Same file and shape pi's own `/trust` command writes: `{ "<canonical dir>": true }`.
    static func trustProject(_ projectDirectory: URL) throws {
        var decisions: [String: Any] = [:]
        if let data = try? Data(contentsOf: trustFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            decisions = existing
        }
        decisions[canonical(projectDirectory)] = true
        try FileManager.default.createDirectory(at: trustFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: decisions, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: trustFile, options: .atomic)
    }
}
