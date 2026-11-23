import Foundation

// MARK: - Contact values the app can hold

/// The seven standard contact values a Lead Generation form can ask the app for. No other key exists.
///
/// The cases are the interactive experience contract's `prefillKeys`, in the contract's order.
public enum StandardAttributeKey: String, CaseIterable, Codable, Sendable {
    case firstName, lastName, fullName, email, phone, age, gender
}

/// Supplied by the app when it opts in.
///
/// The SDK reads `availableKeys` each time a request is built, so it must answer from memory,
/// without reading or fetching any value. Only key names leave the device.
///
/// ``value(for:)`` is called only after the viewer opened a form, only for the keys that form
/// requests and `availableKeys` holds. Values go to that form's page and nowhere else.
public protocol LeadFormValueProvider: AnyObject {
    var availableKeys: Set<StandardAttributeKey> { get }

    /// The value the app holds for `key`, or `nil` to leave that field empty.
    ///
    /// Answer from what the app already has: never fetch from a server just for this. The SDK waits
    /// 1.5 seconds in all for every key it asks about; a value that arrives later is discarded.
    /// A value is dropped when blank, longer than 256 characters, or, for `gender`, not one of
    /// `female`, `male`, `other`, `prefer_not_to_say`.
    func value(for key: StandardAttributeKey) async -> String?
}

public extension LeadFormValueProvider {
    /// Holds no values: every field stays empty.
    func value(for key: StandardAttributeKey) async -> String? {
        nil
    }
}

// MARK: - Opt-in state

/// Shared, mutable holder for the interactive-experience opt-in.
///
/// `AdMoai` is a struct, so an opt-in stored inline would fork across copies; the box makes every
/// copy share one opt-in, the way ``SessionBox`` shares the Journey session. It holds the provider
/// strongly; ``AdMoai/disableInteractiveExperiences()`` releases it.
///
/// It is also the one place that knows every live form controller (weakly) and how many hidden
/// forms are being prepared, so the bound on those and the disposal on a user or opt-in change
/// cover every copy of `AdMoai`. They are NOT process-wide across two separate `AdMoai(config:)`
/// values, which have separate boxes: an app has one.
internal final class InteractiveExperienceBox: @unchecked Sendable {
    private struct LiveController {
        weak var controller: LeadFormController?
    }

    private let lock = NSLock()
    private var provider: LeadFormValueProvider?
    private var supportsSecureFormView: Bool
    private var currentGeneration = 0
    private var live: [LiveController] = []
    /// At most `maxHiddenPreparedForms` forms prepared while never opened.
    let hiddenFormGate = HiddenFormGate()

    init() {
        // The secure form surface is a WKWebView hosted in UIKit: a platform without both (macOS,
        // Linux) cannot show the form, so it never declares support. No insecure fallback.
        #if canImport(WebKit) && canImport(UIKit)
            supportsSecureFormView = true
        #else
            supportsSecureFormView = false
        #endif
    }

    /// Whether this platform can show the secure form view. Settable so tests can exercise the
    /// unsupported branch on a platform that has one.
    var platformSupportsSecureFormView: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return supportsSecureFormView
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            supportsSecureFormView = newValue
        }
    }

    /// Opts in with `newValue`, or out with `nil`. A different provider instance (or none) starts a
    /// new generation and disposes every live controller; the same instance changes nothing.
    ///
    /// The new provider, the new generation and the controllers to dispose are one transaction under
    /// the lock, so no reader sees the new provider with the old generation. Releasing the replaced
    /// provider and the main-actor disposal happen after it.
    func set(_ newValue: LeadFormValueProvider?) {
        lock.lock()
        let previous = provider
        guard previous !== newValue else {
            lock.unlock()
            return
        }
        provider = newValue
        let controllers = advanceGenerationLocked()
        lock.unlock()
        dispose(controllers)
        // The replaced provider is released only now: its deinit may call back into the SDK.
        withExtendedLifetime(previous) {}
    }

    /// The provider and the generation it belongs to, read together under the lock. A reader that
    /// needs both (a controller capturing its opt-in, a lookup starting) must use this, never two
    /// separate reads.
    func snapshot() -> (provider: LeadFormValueProvider?, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (provider, currentGeneration)
    }

    /// The opt-in the lookups and forms created now belong to. Bumped by every change that makes
    /// an in-flight value lookup stale.
    var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return currentGeneration
    }

    /// Registers `controller`, which captured `generation` when it was created. When the opt-in or
    /// the user changed since, it is not registered and is disposed at once, so it never loads.
    @MainActor
    func register(_ controller: LeadFormController, generation: Int) {
        lock.lock()
        guard generation == currentGeneration else {
            lock.unlock()
            controller.dispose()
            return
        }
        live.removeAll { $0.controller == nil }
        live.append(LiveController(controller: controller))
        lock.unlock()
    }

    /// The app switched or cleared its user: forms and lookups prepared for the old one end.
    func userDidChange() {
        lock.lock()
        let controllers = advanceGenerationLocked()
        lock.unlock()
        dispose(controllers)
    }

    /// Starts a new generation and takes the live controllers. The bump is immediate, so a lookup
    /// that completes before the disposal runs is already discarded. Call with the lock held.
    private func advanceGenerationLocked() -> [LeadFormController] {
        currentGeneration += 1
        let controllers = live.compactMap(\.controller)
        live.removeAll()
        return controllers
    }

    /// Disposes on the main actor, outside the lock.
    private func dispose(_ controllers: [LeadFormController]) {
        guard !controllers.isEmpty else { return }
        Task { @MainActor in
            controllers.forEach { $0.dispose() }
        }
    }

    /// Opted in AND the platform has a secure form view.
    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return provider != nil && supportsSecureFormView
    }

    /// The capability to declare on a request, or nil when nothing must be declared. Reads the
    /// provider's key names once; never asks for a value.
    func capability() -> InteractiveExperienceCapability? {
        lock.lock()
        let current = (supportsSecureFormView ? provider : nil)
        lock.unlock()
        guard let current else { return nil }
        let keys = current.availableKeys
        return InteractiveExperienceCapability(
            supported: true,
            availableAttributeKeys: StandardAttributeKey.allCases.filter { keys.contains($0) }
        )
    }
}

// MARK: - Request side

/// The `interactiveExperience` request extension: the SDK can open an interactive experience, and
/// which contact values (names only, never values) the app holds.
public struct InteractiveExperienceCapability: Encodable, Equatable, Sendable {
    /// Always true when the extension is present.
    public let supported: Bool
    /// Deduplicated, in ``StandardAttributeKey`` declaration order.
    public let availableAttributeKeys: [StandardAttributeKey]
}

// MARK: - Response side

/// The interactive experience a creative carries, when it carries one.
public enum InteractiveExperience: Equatable {
    case leadGeneration(LeadGenerationExperience)
    /// Present but unusable: unknown type (its string) or a malformed object (nil or the type).
    /// The app must not show this creative: there is nothing for a tap to open.
    case unsupported(type: String?)
}

/// A prepared Lead Generation form instance the viewer can open.
public struct LeadGenerationExperience: Equatable {
    public let formId: String
    public let preparedVersionId: String
    public let formInstanceId: String
    /// Never public: the form is opened by the SDK, not by the app. Not a secret, so it is printed.
    let launchUrl: URL
    public let expiresAt: Date
    public let prefillAttributeKeys: [StandardAttributeKey]
    /// Never public and never printed: it authorises opening this form instance.
    let preparationToken: String
}

// MARK: - Redaction

extension LeadGenerationExperience: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "LeadGenerationExperience(formId: \(formId), preparedVersionId: \(preparedVersionId), "
            + "formInstanceId: \(formInstanceId), launchUrl: \(launchUrl), expiresAt: \(expiresAt), "
            + "prefillAttributeKeys: \(prefillAttributeKeys.map(\.rawValue)), preparationToken: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "formId": formId,
            "preparedVersionId": preparedVersionId,
            "formInstanceId": formInstanceId,
            "launchUrl": launchUrl,
            "expiresAt": expiresAt,
            "prefillAttributeKeys": prefillAttributeKeys,
            "preparationToken": "<redacted>",
        ], displayStyle: .struct)
    }
}

extension InteractiveExperience: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        switch self {
        case let .leadGeneration(experience): "InteractiveExperience.leadGeneration(\(experience))"
        case let .unsupported(type): "InteractiveExperience.unsupported(type: \(type ?? "nil"))"
        }
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        switch self {
        case let .leadGeneration(experience):
            Mirror(self, children: ["leadGeneration": experience], displayStyle: .enum)
        case let .unsupported(type):
            Mirror(self, children: ["unsupported": type as Any], displayStyle: .enum)
        }
    }
}

// MARK: - Tolerant decoding

extension InteractiveExperience {
    static let leadGenerationType = "lead_generation"

    /// Total reader of a creative's `interactiveExperience` key: never throws. Absent or null is
    /// `nil`; anything present but unusable is ``unsupported(type:)``.
    static func read<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) -> InteractiveExperience? {
        guard container.contains(key), (try? container.decodeNil(forKey: key)) != true else { return nil }
        guard let wire = try? container.decode(Wire.self, forKey: key),
              let type = wire.type else { return .unsupported(type: nil) }
        guard type == leadGenerationType,
              let experience = wire.leadGeneration() else { return .unsupported(type: type) }
        return .leadGeneration(experience)
    }

    private struct Wire: Decodable {
        private enum Keys: String, CodingKey {
            case type, formId, preparedVersionId, formInstanceId, launchUrl
            case preparationToken, expiresAt, prefillAttributeKeys
        }

        let type: String?
        let formId: String?
        let preparedVersionId: String?
        let formInstanceId: String?
        let launchUrl: String?
        let preparationToken: String?
        let expiresAt: String?
        let prefillAttributeKeys: [StandardAttributeKey]

        /// Throws only when the value is not an object.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            type = try? c.decode(String.self, forKey: .type)
            formId = try? c.decode(String.self, forKey: .formId)
            preparedVersionId = try? c.decode(String.self, forKey: .preparedVersionId)
            formInstanceId = try? c.decode(String.self, forKey: .formInstanceId)
            launchUrl = try? c.decode(String.self, forKey: .launchUrl)
            preparationToken = try? c.decode(String.self, forKey: .preparationToken)
            expiresAt = try? c.decode(String.self, forKey: .expiresAt)
            var seen = Set<StandardAttributeKey>()
            prefillAttributeKeys =
                ((try? c.decode([SafelyDecodable<String>].self, forKey: .prefillAttributeKeys)) ?? [])
                    .compactMap { $0.value.flatMap(StandardAttributeKey.init(rawValue:)) }
                    .filter { seen.insert($0).inserted }
        }

        func leadGeneration() -> LeadGenerationExperience? {
            guard let formId, !formId.isEmpty,
                  let preparedVersionId, !preparedVersionId.isEmpty,
                  let formInstanceId, !formInstanceId.isEmpty,
                  let preparationToken, !preparationToken.isEmpty,
                  let launchUrl, let url = URL(string: launchUrl),
                  url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                  let expiresAt, let date = Wire.parseDate(expiresAt)
            else { return nil }
            return LeadGenerationExperience(
                formId: formId,
                preparedVersionId: preparedVersionId,
                formInstanceId: formInstanceId,
                launchUrl: url,
                expiresAt: date,
                prefillAttributeKeys: prefillAttributeKeys,
                preparationToken: preparationToken
            )
        }

        private static func parseDate(_ string: String) -> Date? {
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) {
                return date
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string)
        }
    }
}

// MARK: - AdMoai opt-in

public extension AdMoai {
    /// Opts this app in to interactive experiences (Lead Generation forms).
    ///
    /// From now on every request this SDK builds declares that it can open one, and the names of
    /// the contact values `valueProvider.availableKeys` holds, never the values. Shared by every
    /// copy of this `AdMoai` value. The SDK holds `valueProvider` strongly until
    /// ``disableInteractiveExperiences()``.
    ///
    /// Lead Generation is served only on API version `2025-11-01`.
    func enableInteractiveExperiences(valueProvider: LeadFormValueProvider) {
        interactiveExperienceBox.set(valueProvider)
    }

    /// Opts out: requests stop declaring support and the provider is released.
    func disableInteractiveExperiences() {
        interactiveExperienceBox.set(nil)
    }

    /// Whether this app opted in AND the platform has a secure form view.
    var interactiveExperiencesEnabled: Bool {
        interactiveExperienceBox.isEnabled
    }

    /// For scenario runners on hosts without a secure form view (Linux, macOS CLI): declares what a
    /// capable device would. Never call it in an app.
    @_spi(Testing)
    func assumeSecureFormViewForTesting(_ value: Bool) {
        interactiveExperienceBox.platformSupportsSecureFormView = value
    }

    /// What this host's secure form view support currently is, so a runner can put it back.
    @_spi(Testing)
    var platformSupportsSecureFormViewForTesting: Bool {
        interactiveExperienceBox.platformSupportsSecureFormView
    }
}
