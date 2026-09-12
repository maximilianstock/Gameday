import AppKit
import Foundation
import Observation

struct AppUpdate: Equatable, Sendable {
    let version: String
    let downloadURL: URL
    let releaseURL: URL
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppUpdate)
    case downloading(AppUpdate, Double?)
    case installing(AppUpdate)
    case failed(String, AppUpdate?)
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noAsset
    case invalidArchive
    case wrongBundle
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "GitHub answered with status \(code)."
        case .noAsset: return "The release has no download."
        case .invalidArchive: return "The download couldn't be unpacked."
        case .wrongBundle: return "The download isn't a Gameday build."
        case .commandFailed(let name): return "\(name) failed."
        }
    }
}

/// Checks GitHub releases for a newer build and installs it in place, then relaunches.
/// Deliberately small: one repository, one zip asset per release, HTTPS trust only.
@MainActor
@Observable
final class UpdateController {
    static let repository = "maximilianstock/Gameday"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    private static let dismissedVersionKey = "dismissedUpdateVersion"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    private(set) var state: UpdateState = .idle
    private(set) var lastCheck: Date?

    private let defaults: UserDefaults
    private var timer: Timer?
    private var resetTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The update to show in the banner, unless the user dismissed this version.
    var pendingUpdate: AppUpdate? {
        switch state {
        case .available(let update):
            return update.version == dismissedVersion ? nil : update
        case .downloading(let update, _), .installing(let update):
            return update
        case .failed(_, let update):
            return update
        default:
            return nil
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .installing: return true
        default: return false
        }
    }

    private var dismissedVersion: String? {
        get { defaults.string(forKey: Self.dismissedVersionKey) }
        set { defaults.set(newValue, forKey: Self.dismissedVersionKey) }
    }

    // MARK: Location

    enum AppLocation {
        case applications
        case translocated
        case other
    }

    static var appLocation: AppLocation {
        let path = Bundle.main.bundleURL.path
        if path.contains("/AppTranslocation/") { return .translocated }
        if path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") { return .applications }
        return .other
    }

    /// True when the running bundle can be swapped for a new one.
    var canInstallInPlace: Bool {
        guard Self.appLocation != .translocated else { return false }
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parent)
    }

    // MARK: Checking

    func startAutomaticChecks(initialDelay: TimeInterval = 15) {
        timer?.invalidate()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(initialDelay))
            await self?.check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) async {
        if isBusy { return }
        resetTask?.cancel()
        if userInitiated { state = .checking }
        do {
            let update = try await Self.latestUpdate(newerThan: currentVersion)
            lastCheck = Date()
            if let update {
                if userInitiated { dismissedVersion = nil }
                state = .available(update)
            } else {
                state = .upToDate
                if userInitiated { scheduleReset() } else { state = .idle }
            }
        } catch {
            lastCheck = Date()
            if userInitiated {
                state = .failed(error.localizedDescription, nil)
                scheduleReset(after: 6)
            } else if case .checking = state {
                state = .idle
            }
        }
    }

    func dismissPendingUpdate() {
        if case .available(let update) = state {
            dismissedVersion = update.version
        }
        if case .failed = state { state = .idle }
    }

    private func scheduleReset(after seconds: Double = 5) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            switch self.state {
            case .upToDate, .failed(_, nil): self.state = .idle
            default: break
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String
        }
        let tagName: String
        let htmlUrl: String
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    private static func latestUpdate(newerThan current: String) async throws -> AppUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        if release.draft == true || release.prerelease == true { return nil }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        guard isVersion(version, newerThan: current) else { return nil }
        guard let asset = release.assets.first(where: { $0.name.hasPrefix("Gameday") && $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: asset.browserDownloadUrl),
              let releaseURL = URL(string: release.htmlUrl)
        else { throw UpdateError.noAsset }
        return AppUpdate(version: version, downloadURL: downloadURL, releaseURL: releaseURL)
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate)
        let b = parts(current)
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Installing

    func install() async {
        let update: AppUpdate
        switch state {
        case .available(let pending), .failed(_, let pending?): update = pending
        default: return
        }
        guard canInstallInPlace else {
            NSWorkspace.shared.open(update.releaseURL)
            return
        }
        state = .downloading(update, nil)
        do {
            let archive = try await download(update.downloadURL) { [weak self] fraction in
                self?.state = .downloading(update, fraction)
            }
            state = .installing(update)
            let bundleID = Bundle.main.bundleIdentifier ?? "stockdev.Gameday"
            let newApp = try await Task.detached(priority: .userInitiated) {
                try Self.unpackAndValidate(archive: archive, expectedVersion: update.version, bundleID: bundleID)
            }.value
            try Self.replaceCurrentApp(with: newApp)
            Self.relaunch()
        } catch {
            state = .failed(error.localizedDescription, update)
        }
    }

    private func download(_ url: URL, progress: @escaping @MainActor (Double?) -> Void) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw UpdateError.badResponse(http.statusCode)
        }
        let expected = response.expectedContentLength
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GamedayUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("Gameday.zip")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(256 * 1024)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(expected > 0 ? Double(received) / Double(expected) : nil)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        progress(1)
        return destination
    }

    nonisolated private static func unpackAndValidate(archive: URL, expectedVersion: String, bundleID: String) throws -> URL {
        let directory = archive.deletingLastPathComponent().appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.invalidArchive }
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == bundleID,
              let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              version == expectedVersion
        else { throw UpdateError.wrongBundle }
        // The download carries the quarantine flag; without this Gatekeeper would block the new build.
        try? run("/usr/bin/xattr", ["-rd", "com.apple.quarantine", app.path])
        return app
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(URL(fileURLWithPath: executable).lastPathComponent)
        }
    }

    private static func replaceCurrentApp(with newApp: URL) throws {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            // Fall back to trash + move when an atomic replace isn't possible.
            try FileManager.default.trashItem(at: current, resultingItemURL: nil)
            try FileManager.default.moveItem(at: newApp, to: current)
        }
    }

    private static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"\(path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }
}
