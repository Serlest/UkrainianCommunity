import Combine
import FirebaseAuth
import FirebaseFunctions
import Foundation
import UIKit
import Network

/// Banner measurement has its own server-confirmed consent. The content analytics
/// setting cannot grant this purpose, and an old local choice never enables it.
@MainActor
final class BannerMeasurementService: ObservableObject {
    private static let privacyVersion = "2026.21"
    private static let disclosureVersion = "2026-10-19.1"
    private static let pendingWithdrawalKey = "bannerMeasurementPendingWithdrawal.v1"

    @Published private(set) var isAvailable = false
    @Published private(set) var isEnabled = false
    @Published private(set) var allowsRegionalMeasurement = false
    @Published private(set) var isBusy = false
    @Published private(set) var hasError = false
    @Published private(set) var hasLoaded = false
    var canConfigure: Bool { principalID != nil }
    private let principalProvider: () -> String?
    private let backendCall: (String, [String: Any]) async throws -> [String: Any]
    private var identityGeneration: UInt64 = 0

    private let defaults: UserDefaults
    private let outbox: BannerMeasurementQueueStore
    private var principalID: String?
    private var consentID: String?
    private var isDelivering = false
    private var stateGeneration: UInt64 = 0
    private var retryAfter: Date?
    private var retryTask: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var authHandle: NSObjectProtocol?
    private var foregroundHandle: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, startsObservers: Bool = true,
         principalProvider: (() -> String?)? = nil,
         backendCall: ((String, [String: Any]) async throws -> [String: Any])? = nil) {
        self.defaults = defaults
        self.principalProvider = principalProvider ?? Self.verifiedUserID
        self.backendCall = backendCall ?? { name, payload in
            let callable = Functions.functions(region: "europe-west3").httpsCallable(name)
            callable.timeoutInterval = 15
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else { throw AppError.validationFailed }
            return data
        }
        principalID = self.principalProvider()
        outbox = BannerMeasurementQueueStore(
            defaults: defaults, principalID: principalID, loadExisting: startsObservers
        )
        guard startsObservers else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshIdentity() }
        }
        foregroundHandle = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let withdrawing = self.principalID.map { self.pendingWithdrawal(for: $0) != nil } ?? false
                guard self.hasError || self.outbox.first != nil || withdrawing else { return }
                self.retryAfter = nil
                await self.refresh()
            }
        }
        monitor.start(queue: DispatchQueue(label: "uac.banner-measurement.network"))
        networkMonitor = monitor
        Task { await refresh() }
    }

    deinit {
        networkMonitor?.cancel()
        retryTask?.cancel()
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        if let foregroundHandle { NotificationCenter.default.removeObserver(foregroundHandle) }
    }

    func record(_ measurement: FeaturedBannerMeasurement) {
        refreshIdentityIfNeeded()
        guard isEnabled, let consentID, principalID != nil else { return }
        var permittedMeasurement = measurement
        if !allowsRegionalMeasurement { permittedMeasurement.displayRegion = nil }
        outbox.append(BannerMeasurementQueuedEvent(permittedMeasurement, consentID: consentID))
        Task { await deliverPending() }
    }

    func refresh() async {
        refreshIdentityIfNeeded()
        guard let principalID, !isBusy else { return }
        stateGeneration &+= 1
        let generation = stateGeneration
        isBusy = true
        defer { if stateGeneration == generation { isBusy = false } }
        if let withdrawalID = pendingWithdrawal(for: principalID) {
            guard await sendChoice(enabled: false, consentID: withdrawalID, principalID: principalID, generation: generation) else { return }
            setPendingWithdrawal(nil, for: principalID)
        }
        do {
            let data = try await backendCall("getBannerMeasurementConsent", [:])
            guard self.principalID == principalID, stateGeneration == generation else { return }
            guard let available = data["available"] as? Bool, let enabled = data["enabled"] as? Bool else {
                throw AppError.validationFailed
            }
            let grantedID = data["consentID"] as? String
            guard !enabled || (available && grantedID?.isEmpty == false) else { throw AppError.validationFailed }
            hasLoaded = true
            isAvailable = available
            isEnabled = available && enabled
            consentID = isEnabled ? grantedID : nil
            allowsRegionalMeasurement = isEnabled && data["allowsRegion"] as? Bool == true
            if !isEnabled { outbox.removeAll() }
            hasError = false
            retryAfter = nil
            if isEnabled { Task { await deliverPending() } }
        } catch {
            // No cached grant: a failed server read cannot silently enable collection.
            guard self.principalID == principalID, stateGeneration == generation else { return }
            isEnabled = false
            consentID = nil
            allowsRegionalMeasurement = false
            hasError = true
        }
    }

    func setEnabled(_ enabled: Bool) async {
        refreshIdentityIfNeeded()
        guard let principalID, !isBusy else { return }
        stateGeneration &+= 1
        let generation = stateGeneration
        if enabled {
            guard isAvailable, !isEnabled, pendingWithdrawal(for: principalID) == nil else { return }
            let proposedID = UUID().uuidString.lowercased()
            isBusy = true
            defer { if stateGeneration == generation { isBusy = false } }
            if await sendChoice(enabled: true, consentID: proposedID, principalID: principalID, generation: generation) {
                guard self.principalID == principalID, stateGeneration == generation else { return }
                consentID = proposedID
                isEnabled = true
                allowsRegionalMeasurement = true
                hasError = false
            }
        } else {
            guard let consentID else { return }
            // Stop locally before awaiting a network response. Persist a withdrawal
            // so it is retried after a connection loss or app restart.
            isEnabled = false
            self.consentID = nil
            allowsRegionalMeasurement = false
            retryTask?.cancel()
            outbox.removeAll()
            setPendingWithdrawal(consentID, for: principalID)
            isBusy = true
            defer { if stateGeneration == generation { isBusy = false } }
            if await sendChoice(enabled: false, consentID: consentID, principalID: principalID, generation: generation) {
                setPendingWithdrawal(nil, for: principalID)
                hasError = false
            }
        }
    }

    private func sendChoice(enabled: Bool, consentID: String, principalID: String, generation: UInt64) async -> Bool {
        do {
            let payload: [String: Any] = [
                "enabled": enabled, "consentID": consentID,
                "locale": LocalizationStore.language.rawValue == "uk" ? "uk" : "de",
                "privacyVersion": Self.privacyVersion,
                "disclosureVersion": Self.disclosureVersion,
            ]
            let data = try await backendCall("updateBannerMeasurementConsent", payload)
            guard self.principalID == principalID, stateGeneration == generation else { return false }
            guard data["enabled"] as? Bool == enabled, data["consentID"] as? String == consentID else {
                hasError = true
                return false
            }
            return true
        } catch {
            if self.principalID == principalID && stateGeneration == generation { hasError = true }
            return false
        }
    }

    private func deliverPending() async {
        guard !isDelivering, let principalID, let consentID, isEnabled,
              retryAfter.map({ Date() >= $0 }) ?? true else { return }
        isDelivering = true
        defer {
            isDelivering = false
            if isEnabled && (self.principalID != principalID || self.consentID != consentID) {
                Task { await deliverPending() }
            }
        }
        outbox.prune()
        while let event = outbox.first, self.principalID == principalID,
              self.consentID == consentID, isEnabled {
            guard event.consentID == consentID else {
                outbox.removeFirst(); continue
            }
            do {
                _ = try await backendCall("recordBannerMeasurement", event.payload)
                guard self.principalID == principalID, self.consentID == consentID else { return }
                outbox.removeFirst()
            } catch {
                guard self.principalID == principalID, self.consentID == consentID else { return }
                // Keep the same event ID for retry; the server receipt prevents
                // a double count if the acknowledgement was lost.
                let failure = error as NSError
                if failure.domain == FunctionsErrorDomain,
                   [FunctionsErrorCode.invalidArgument.rawValue,
                    FunctionsErrorCode.notFound.rawValue].contains(failure.code) {
                    outbox.removeFirst()
                    continue
                }
                if failure.domain == FunctionsErrorDomain,
                   [FunctionsErrorCode.failedPrecondition.rawValue,
                    FunctionsErrorCode.permissionDenied.rawValue,
                    FunctionsErrorCode.unauthenticated.rawValue].contains(failure.code) {
                    outbox.removeAll()
                    isEnabled = false
                    self.consentID = nil
                    Task { await refresh() }
                } else {
                    retryAfter = Date().addingTimeInterval(
                        failure.domain == FunctionsErrorDomain
                            && failure.code == FunctionsErrorCode.resourceExhausted.rawValue ? 300 : 60
                    )
                    scheduleRetry()
                }
                return
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        guard let retryAfter else { return }
        let delay = max(1, retryAfter.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.deliverPending()
        }
    }

    func renewRegionalConsent() async {
        // The updated disclosure is shown before this method is called.
        let identity = identityGeneration
        let userID = principalID
        if isEnabled {
            await setEnabled(false)
            guard !hasError, identityGeneration == identity, principalID == userID else { return }
        }
        guard identityGeneration == identity, principalID == userID else { return }
        await setEnabled(true)
    }

    private func refreshIdentityIfNeeded() {
        let current = principalProvider()
        guard principalID != current else { return }
        refreshIdentity()
    }

    private func refreshIdentity() {
        let current = principalProvider()
        guard principalID != current else { return }
        stateGeneration &+= 1
        identityGeneration &+= 1
        isBusy = false
        hasError = false
        hasLoaded = false
        retryAfter = nil
        retryTask?.cancel()
        allowsRegionalMeasurement = false
        principalID = current
        isEnabled = false
        isAvailable = false
        consentID = nil
        outbox.switchPrincipal(to: current)
        Task { await refresh() }
    }

    private func pendingWithdrawal(for principalID: String) -> String? {
        defaults.dictionary(forKey: Self.pendingWithdrawalKey)?[principalID] as? String
    }

    private func setPendingWithdrawal(_ consentID: String?, for principalID: String) {
        var pending = defaults.dictionary(forKey: Self.pendingWithdrawalKey) ?? [:]
        pending[principalID] = consentID
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.pendingWithdrawalKey)
        } else {
            defaults.set(pending, forKey: Self.pendingWithdrawalKey)
        }
    }

    private static func verifiedUserID() -> String? {
        guard let user = Auth.auth().currentUser, !user.isAnonymous,
              user.isEmailVerified else { return nil }
        return user.uid
    }
}
