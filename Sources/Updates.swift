import AppKit
import Combine

/// Asks GitHub for the latest release a few seconds after launch and every 8 hours after that.
/// No token and no user data: only a User-Agent with the app version and an ETag, so an unchanged
/// answer doesn't count against GitHub's limit.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// The last known release (from the network or the cache). UpdatePolicy decides whether it's newer.
    @Published private(set) var latest: ReleaseInfo?
    @Published private(set) var dismissed: String? { didSet { d.set(dismissed, forKey: Keys.dismissed) } }
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let homebrew = UpdatePolicy.isHomebrewInstall()

    private let d = UserDefaults.standard
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral // no cookies and no disk cache: the ETag is handled here
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private enum Keys {
        static let etag = "updateETag", release = "updateRelease", checkedAt = "updateCheckedAt"
        static let dismissed = "updateDismissed"
    }

    private init() {
        latest = d.data(forKey: Keys.release).flatMap { try? JSONDecoder().decode(ReleaseInfo.self, from: $0) }
        dismissed = d.string(forKey: Keys.dismissed)
        lastChecked = d.object(forKey: Keys.checkedAt) as? Date
    }

    /// The release to show a banner for, if any.
    var available: ReleaseInfo? {
        UpdatePolicy.showBanner(latest, current: current, checkOn: Settings.shared.updateCheck, dismissed: dismissed)
            ? latest : nil
    }

    /// Hides the banner until the next version.
    func dismissBanner() { dismissed = latest?.version }

    func start() {
        Settings.shared.$updateCheck.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.apply(on) }.store(in: &bag)
        // After sleep the timer may have missed its deadline: check soon after waking if it's due.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self?.checkIfDue() }
        }
    }

    private func apply(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        objectWillChange.send() // the banner follows the switch
        guard on else { return }
        // Every launch checks, a few seconds in so the network is up: quitting and reopening is how
        // people look for an update.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.check() }
        // The timer only wakes the deadline check, so the 8 hours also count through sleep.
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.checkIfDue() }
        timer?.tolerance = 300
    }

    private func checkIfDue() {
        guard Settings.shared.updateCheck, UpdatePolicy.isDue(lastCheck: lastChecked, now: Date()) else { return }
        check()
    }

    /// Asks GitHub. Offline, rate-limited or any other error: quietly wait for the next time.
    func check() {
        guard !checking, Settings.shared.updateCheck else { return }
        checking = true
        var request = URLRequest(url: UpdatePolicy.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("DualPad/\(current)", forHTTPHeaderField: "User-Agent")
        if latest != nil, let etag = d.string(forKey: Keys.etag) { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        session.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async { self?.handle(data, response as? HTTPURLResponse) }
        }.resume()
    }

    private func handle(_ data: Data?, _ response: HTTPURLResponse?) {
        checking = false
        guard let response else { return } // offline: keep the deadline, try again in half an hour
        lastChecked = Date()
        d.set(lastChecked, forKey: Keys.checkedAt)
        switch response.statusCode {
        case 304:
            break // nothing new
        case 200:
            guard let data, let release = UpdatePolicy.parse(data) else { return }
            d.set(response.value(forHTTPHeaderField: "ETag"), forKey: Keys.etag)
            d.set(try? JSONEncoder().encode(release), forKey: Keys.release)
            if release != latest { latest = release }
        case 404:
            // No release at all: forget the cached one.
            d.removeObject(forKey: Keys.etag)
            d.removeObject(forKey: Keys.release)
            latest = nil
        default:
            return // 403/429: rate limit, wait for the regular deadline
        }
    }
}
