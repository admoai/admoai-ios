import Foundation

// MARK: - JSON value

/// A decoded JSON value that keeps booleans distinct from numbers, so a payload field typed
/// `boolean` is never satisfied by `1`.
enum JSONValue: Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else if let value = try? c.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(value): try c.encode(value)
        case let .number(value): try c.encode(value)
        case let .string(value): try c.encode(value)
        case let .array(value): try c.encode(value)
        case let .object(value): try c.encode(value)
        }
    }
}

// MARK: - Envelope

/// One bridge message on the wire: `{type, instanceId, channel, payload}`.
struct BridgeEnvelope: Equatable, Codable {
    var type: String
    var instanceId: String
    var channel: String
    var payload: [String: JSONValue]

    /// The compact JSON text the page receives.
    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }

    /// Reads one envelope. Anything that is not exactly the four envelope keys is refused.
    static func decode(_ string: String) -> Result<BridgeEnvelope, BridgeRejection> {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: Data(string.utf8)) else {
            return .failure(.notJSON)
        }
        guard case let .object(fields) = root,
              Set(fields.keys) == ["type", "instanceId", "channel", "payload"],
              case let .string(type)? = fields["type"],
              case let .string(instanceId)? = fields["instanceId"],
              case let .string(channel)? = fields["channel"],
              case let .object(payload)? = fields["payload"]
        else { return .failure(.malformedEnvelope) }
        return .success(BridgeEnvelope(type: type, instanceId: instanceId, channel: channel, payload: payload))
    }
}

// MARK: - Refusals

/// Why a bridge message was refused. Carries schema-known names only (a message type the table
/// knows, a field name the table knows), never a value the page or the app supplied: a refusal is
/// logged, and the preparation token and prefill values must never reach a log.
enum BridgeRejection: Error, Equatable, CustomStringConvertible {
    enum Fault: Error, Equatable {
        case missingField(String)
        case unknownField
        case wrongType(String)
        case notAllowed(String)
        case badFormat(String)
        case tooLong(String)
        case insecureURL(String)
        case duplicate(String)
    }

    case oversize
    case notJSON
    case malformedEnvelope
    case wrongInstance
    case wrongChannel
    case unknownType
    case wrongDirection(type: String)
    case outOfOrder(type: String)
    case notAllowedNow(type: String)
    case invalidPayload(type: String, fault: Fault)

    /// A `bridge_ready` that names a bridge version this SDK does not speak.
    var isUnsupportedBridgeVersion: Bool {
        if case .invalidPayload(type: "bridge_ready", fault: .notAllowed("bridgeVersion")) = self {
            return true
        }
        return false
    }

    var description: String {
        switch self {
        case .oversize: "message over the size limit"
        case .notJSON: "message is not JSON"
        case .malformedEnvelope: "message envelope is malformed"
        case .wrongInstance: "message names another form instance"
        case .wrongChannel: "message names another channel"
        case .unknownType: "unknown message type"
        case let .wrongDirection(type): "\(type) is not valid in this direction"
        case let .outOfOrder(type): "\(type) arrived out of order"
        case let .notAllowedNow(type): "\(type) is not allowed in the current state"
        case let .invalidPayload(type, fault): "\(type) payload refused: \(Self.describe(fault))"
        }
    }

    private static func describe(_ fault: Fault) -> String {
        switch fault {
        case let .missingField(name): "\(name) is missing"
        case .unknownField: "an unknown field"
        case let .wrongType(name): "\(name) has the wrong type"
        case let .notAllowed(name): "\(name) is not an allowed value"
        case let .badFormat(name): "\(name) has the wrong format"
        case let .tooLong(name): "\(name) is too long"
        case let .insecureURL(name): "\(name) is not an https URL"
        case let .duplicate(name): "\(name) repeats an entry"
        }
    }
}

// MARK: - Typed vocabulary

/// The form events the SDK reports, from the contract's `activated.events[].name` enum.
enum LeadFormEvent: String, CaseIterable, Hashable {
    case formOpen = "form_open"
    case formStart = "form_start"
    case websiteCtaClick = "website_cta_click"
}

/// The error codes a form can report, a subset of `error-codes.json`.
enum LeadFormErrorCode: String, CaseIterable, Equatable {
    case unauthorized, expired, revoked
    case formNotAvailable = "form_not_available"
    case rateLimited = "rate_limited"
    case temporaryFailure = "temporary_failure"
    case invalidFieldValue = "invalid_field_value"
    case conflictingAcceptedPayload = "conflicting_accepted_payload"

    /// Whether trying again can help, as `error-codes.json` states per code. A form's own
    /// `retryable` flag can only narrow this, never widen it.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .temporaryFailure: true
        case .unauthorized, .expired, .revoked, .formNotAvailable, .invalidFieldValue,
             .conflictingAcceptedPayload: false
        }
    }
}

enum ExternalURLPurpose: String, Equatable {
    case privacyPolicy = "privacy_policy"
    case websiteCta = "website_cta"
}

/// How the app shows the form; the wire value is the raw value.
@_spi(InteractiveExperience)
public enum LeadFormPresentation: String, Equatable, Sendable {
    case inline
    case fullScreen = "full_screen"
}

// MARK: - Messages

/// A validated message from the form.
enum RuntimeMessage: Equatable {
    case bridgeReady(runtimeVersion: String, bridgeVersion: String)
    case prepared(preparedVersionId: String)
    case activated(formVersionId: String, requestedAttributeKeys: [StandardAttributeKey], events: [LeadFormEvent: URL])
    case prefillApplied
    case prepareFailed(code: LeadFormErrorCode, retryable: Bool)
    case fatalError(code: LeadFormErrorCode)
    case requestClose
    case requestExternalURL(purpose: ExternalURLPurpose, url: URL)
    case event(name: LeadFormEvent)
    case submitting
    case submitFailed(code: LeadFormErrorCode, retryable: Bool)
    case submitted(leadId: String, submittedAt: Date)

    /// The contract's `type`.
    var wireType: String {
        switch self {
        case .bridgeReady: "bridge_ready"
        case .prepared: "prepared"
        case .activated: "activated"
        case .prefillApplied: "prefill_applied"
        case .prepareFailed: "prepare_failed"
        case .fatalError: "fatal_error"
        case .requestClose: "request_close"
        case .requestExternalURL: "request_external_url"
        case .event: "event"
        case .submitting: "submitting"
        case .submitFailed: "submit_failed"
        case .submitted: "submitted"
        }
    }
}

/// A message the app sends. Its description never shows the token or a value.
enum AppMessage: Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case initialize(preparationToken: String, presentation: LeadFormPresentation)
    case activate
    case prefill(values: [StandardAttributeKey: String])
    case becameVisible
    case becameHidden
    /// The viewer pressed the system back button while the form was visible.
    case back
    case retryPrepare
    case dispose

    var wireType: String {
        switch self {
        case .initialize: "initialize"
        case .activate: "activate"
        case .prefill: "prefill"
        case .becameVisible: "became_visible"
        case .becameHidden: "became_hidden"
        case .back: "back"
        case .retryPrepare: "retry_prepare"
        case .dispose: "dispose"
        }
    }

    var description: String {
        "AppMessage(\(wireType))"
    }

    var debugDescription: String {
        description
    }

    /// Redacted: a dump or `String(reflecting:)` must not show the token or a value either.
    var customMirror: Mirror {
        Mirror(self, children: ["type": wireType], displayStyle: .enum)
    }

    private var payload: [String: JSONValue] {
        switch self {
        case let .initialize(token, presentation):
            ["preparationToken": .string(token), "presentation": .string(presentation.rawValue)]
        case let .prefill(values):
            ["values": .object(Dictionary(uniqueKeysWithValues: values.map { (
                $0.key.rawValue,
                JSONValue.string($0.value)
            ) }))]
        case .activate, .becameVisible, .becameHidden, .back, .retryPrepare, .dispose:
            [:]
        }
    }

    /// The JSON text to send. The same rules incoming messages obey apply here: size, shape,
    /// lengths, and, for `prefill`, only keys the form requested and only a gender it offers.
    ///
    /// - Parameter allowedPrefillKeys: the keys of the last `activated.requestedAttributeKeys`;
    ///   `nil` skips that one check.
    func encode(
        instanceId: String,
        channel: String,
        allowedPrefillKeys: Set<StandardAttributeKey>? = nil
    ) throws -> String {
        if case let .prefill(values) = self {
            if let allowedPrefillKeys, !Set(values.keys).isSubset(of: allowedPrefillKeys) {
                throw BridgeRejection.invalidPayload(type: wireType, fault: .unknownField)
            }
            if let gender = values[.gender], !LeadFormBridge.Limits.genderOptions.contains(gender) {
                throw BridgeRejection.invalidPayload(type: wireType, fault: .notAllowed("values"))
            }
        }
        let text = try BridgeEnvelope(type: wireType, instanceId: instanceId, channel: channel, payload: payload)
            .encoded()
        // Self-check against the table: what leaves is what the form would accept.
        switch LeadFormBridge.validate(text, direction: .appToRuntime, instanceId: instanceId, channel: channel) {
        case .success: return text
        case let .failure(rejection): throw rejection
        }
    }
}

// MARK: - Protocol

/// The bridge protocol of `bridge-messages.json`, vendored in
/// `Tests/AdMoaiTests/Fixtures/interactive-experience/`. The table below is hand-written and a test
/// asserts it equals the contract with no exceptions, so a contract change this SDK has not
/// followed fails the suite.
enum LeadFormBridge {
    enum Direction: String {
        case appToRuntime = "app_to_runtime"
        case runtimeToApp = "runtime_to_app"
    }

    struct Field: Equatable {
        enum Kind: String {
            case string, boolean, timestamp
            case stringMap = "string_map"
            case stringList = "string_list"
            case objectList = "object_list"
            case httpsUrl = "https_url"
        }

        let name: String
        let kind: Kind
        var required = true
        var enumValues: [String]?
        var pattern: String?
        var maxLength: Int?
        /// `string_map` keys and `string_list` items come from the contract's `prefillKeys`.
        var fromPrefillKeys = false
        var uniqueBy: String?
        var items: [Field] = []
    }

    struct Rule: Equatable {
        let type: String
        let direction: Direction
        let after: [String]
        var fields: [Field] = []
    }

    enum Limits {
        static let maxMessageBytes = 16384
        /// Declared only: the hidden-form bound and the prefill lookup are a later item.
        static let maxHiddenPreparedForms = 2
        static let prefillLookupTimeoutMs = 1500
        static let instanceIdPattern = "^form_instance_[0-9A-HJKMNP-TV-Z]{26}$"
        static let channelPattern = "^[A-Za-z0-9_-]{16,64}$"
        /// The bridge versions this SDK speaks.
        static let bridgeVersions = ["1"]
        /// `standard-fields.json` `genderOptions[].value`.
        static let genderOptions = ["female", "male", "other", "prefer_not_to_say"]
        static let prefillKeys = StandardAttributeKey.allCases.map(\.rawValue)
        static let eventNames = LeadFormEvent.allCases.map(\.rawValue)

        private static let versionId = "^form_version_[0-9A-HJKMNP-TV-Z]{26}$"

        static let rules: [Rule] = [
            Rule(type: "initialize", direction: .appToRuntime, after: ["bridge_ready"], fields: [
                Field(name: "preparationToken", kind: .string, maxLength: 4096),
                Field(name: "presentation", kind: .string, enumValues: ["inline", "full_screen"]),
            ]),
            Rule(type: "activate", direction: .appToRuntime, after: ["prepared"]),
            Rule(type: "prefill", direction: .appToRuntime, after: ["activated"], fields: [
                Field(name: "values", kind: .stringMap, maxLength: 256, fromPrefillKeys: true),
            ]),
            Rule(type: "became_visible", direction: .appToRuntime, after: ["prefill_applied"]),
            Rule(type: "became_hidden", direction: .appToRuntime, after: ["became_visible"]),
            Rule(type: "back", direction: .appToRuntime, after: ["became_visible"]),
            Rule(type: "retry_prepare", direction: .appToRuntime, after: ["prepare_failed"]),
            Rule(type: "dispose", direction: .appToRuntime, after: []),
            Rule(type: "bridge_ready", direction: .runtimeToApp, after: [], fields: [
                Field(name: "runtimeVersion", kind: .string, maxLength: 64),
                Field(name: "bridgeVersion", kind: .string, enumValues: bridgeVersions),
            ]),
            Rule(type: "prepared", direction: .runtimeToApp, after: ["initialize", "retry_prepare"], fields: [
                Field(name: "preparedVersionId", kind: .string, pattern: versionId),
            ]),
            Rule(type: "activated", direction: .runtimeToApp, after: ["activate"], fields: [
                Field(name: "formVersionId", kind: .string, pattern: versionId),
                Field(name: "requestedAttributeKeys", kind: .stringList, fromPrefillKeys: true),
                Field(name: "events", kind: .objectList, uniqueBy: "name", items: [
                    Field(name: "name", kind: .string, enumValues: eventNames),
                    Field(name: "url", kind: .httpsUrl),
                ]),
            ]),
            Rule(type: "prefill_applied", direction: .runtimeToApp, after: ["prefill"]),
            Rule(
                type: "prepare_failed",
                direction: .runtimeToApp,
                after: ["initialize", "activate", "retry_prepare"],
                fields: [
                    Field(name: "errorCode", kind: .string, enumValues: [
                        "unauthorized", "expired", "revoked", "form_not_available", "rate_limited", "temporary_failure",
                    ]),
                    Field(name: "retryable", kind: .boolean),
                ]
            ),
            Rule(type: "fatal_error", direction: .runtimeToApp, after: ["bridge_ready"], fields: [
                Field(name: "errorCode", kind: .string, enumValues: ["expired", "revoked", "temporary_failure"]),
            ]),
            Rule(type: "request_close", direction: .runtimeToApp, after: ["bridge_ready"]),
            Rule(type: "request_external_url", direction: .runtimeToApp, after: ["became_visible"], fields: [
                Field(name: "purpose", kind: .string, enumValues: ["privacy_policy", "website_cta"]),
                Field(name: "url", kind: .httpsUrl),
            ]),
            Rule(type: "event", direction: .runtimeToApp, after: ["became_visible"], fields: [
                Field(name: "name", kind: .string, enumValues: eventNames),
            ]),
            Rule(type: "submitting", direction: .runtimeToApp, after: ["became_visible"]),
            Rule(type: "submit_failed", direction: .runtimeToApp, after: ["submitting"], fields: [
                Field(name: "errorCode", kind: .string, enumValues: [
                    "invalid_field_value", "conflicting_accepted_payload", "expired", "revoked",
                    "rate_limited", "temporary_failure",
                ]),
                Field(name: "retryable", kind: .boolean),
            ]),
            Rule(type: "submitted", direction: .runtimeToApp, after: ["submitting"], fields: [
                Field(name: "leadId", kind: .string, pattern: "^lead_[0-9A-HJKMNP-TV-Z]{26}$"),
                Field(name: "submittedAt", kind: .timestamp),
            ]),
        ]

        static func rule(for type: String) -> Rule? {
            rules.first { $0.type == type }
        }
    }

    /// What the controller knows that a message's own text cannot say.
    struct Context: Equatable {
        /// The names of the last `activated.events`; an `event` message must name one of them.
        var activatedEvents: Set<LeadFormEvent> = []
    }

    // MARK: Incoming

    /// Validates one message from the form against the table and the controller's state.
    ///
    /// - Parameters:
    ///   - exchanged: the types already sent or received in this instance.
    static func validateIncoming(
        _ string: String,
        expected instanceId: String,
        channel: String,
        exchanged: Set<String>,
        context: Context = Context()
    ) -> Result<RuntimeMessage, BridgeRejection> {
        switch validate(
            string,
            direction: .runtimeToApp,
            instanceId: instanceId,
            channel: channel,
            exchanged: exchanged
        ) {
        case let .failure(rejection):
            return .failure(rejection)
        case let .success((rule, values)):
            do {
                try check(rule: rule, values: values, exchanged: exchanged, context: context)
            } catch {
                return .failure((error as? BridgeRejection) ?? .malformedEnvelope)
            }
            return .success(RuntimeMessage.make(rule.type, values))
        }
    }

    private static func check(rule: Rule, values: [String: Value], exchanged: Set<String>, context: Context) throws {
        switch rule.type {
        case "request_external_url":
            // A website link follows a submission; the privacy policy only needs the form shown.
            if case .string("website_cta")? = values["purpose"], !exchanged.contains("submitted") {
                throw BridgeRejection.notAllowedNow(type: rule.type)
            }
        case "event":
            if case let .string(name)? = values["name"], let event = LeadFormEvent(rawValue: name),
               !context.activatedEvents.contains(event)
            {
                throw BridgeRejection.notAllowedNow(type: rule.type)
            }
        default:
            break
        }
    }

    // MARK: Shared validation

    /// A payload value after validation.
    indirect enum Value: Equatable {
        case string(String)
        case bool(Bool)
        case stringMap([String: String])
        case stringList([String])
        case objectList([[String: Value]])
        case url(URL)
        case date(Date)
    }

    /// Envelope, identity, type, direction, order (when `exchanged` is given) and payload.
    static func validate(
        _ string: String,
        direction: Direction,
        instanceId: String,
        channel: String,
        exchanged: Set<String>? = nil
    ) -> Result<(Rule, [String: Value]), BridgeRejection> {
        guard string.utf8.count <= Limits.maxMessageBytes else { return .failure(.oversize) }
        let envelope: BridgeEnvelope
        switch BridgeEnvelope.decode(string) {
        case let .success(value): envelope = value
        case let .failure(rejection): return .failure(rejection)
        }
        guard envelope.instanceId == instanceId else { return .failure(.wrongInstance) }
        guard envelope.channel == channel else { return .failure(.wrongChannel) }
        guard matches(envelope.instanceId, Limits.instanceIdPattern),
              matches(envelope.channel, Limits.channelPattern) else { return .failure(.malformedEnvelope) }
        guard let rule = Limits.rule(for: envelope.type) else { return .failure(.unknownType) }
        guard rule.direction == direction else { return .failure(.wrongDirection(type: rule.type)) }
        if let exchanged, !rule.after.isEmpty, exchanged.isDisjoint(with: rule.after) {
            return .failure(.outOfOrder(type: rule.type))
        }
        do {
            return try .success((rule, validate(fields: rule.fields, in: envelope.payload)))
        } catch let fault as BridgeRejection.Fault {
            return .failure(.invalidPayload(type: rule.type, fault: fault))
        } catch {
            return .failure(.malformedEnvelope)
        }
    }

    private static func validate(fields: [Field], in object: [String: JSONValue]) throws -> [String: Value] {
        let known = Set(fields.map(\.name))
        guard Set(object.keys).isSubset(of: known) else { throw BridgeRejection.Fault.unknownField }
        var result: [String: Value] = [:]
        for field in fields {
            guard let raw = object[field.name] else {
                if field.required {
                    throw BridgeRejection.Fault.missingField(field.name)
                }
                continue
            }
            result[field.name] = try validate(field, raw)
        }
        return result
    }

    private static func validate(_ field: Field, _ raw: JSONValue) throws -> Value {
        typealias Fault = BridgeRejection.Fault
        switch field.kind {
        case .string:
            guard case let .string(text) = raw else { throw Fault.wrongType(field.name) }
            try checkString(text, field)
            return .string(text)
        case .boolean:
            guard case let .bool(flag) = raw else { throw Fault.wrongType(field.name) }
            return .bool(flag)
        case .timestamp:
            guard case let .string(text) = raw else { throw Fault.wrongType(field.name) }
            guard let date = parseTimestamp(text) else { throw Fault.badFormat(field.name) }
            return .date(date)
        case .httpsUrl:
            guard case let .string(text) = raw else { throw Fault.wrongType(field.name) }
            guard let url = URL(string: text), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty else { throw Fault.insecureURL(field.name) }
            return .url(url)
        case .stringMap:
            guard case let .object(map) = raw else { throw Fault.wrongType(field.name) }
            var result: [String: String] = [:]
            for (key, value) in map {
                guard Limits.prefillKeys.contains(key) else { throw Fault.unknownField }
                guard case let .string(text) = value else { throw Fault.wrongType(field.name) }
                if let maxLength = field.maxLength, text.unicodeScalars.count > maxLength {
                    throw Fault.tooLong(field.name)
                }
                result[key] = text
            }
            return .stringMap(result)
        case .stringList:
            guard case let .array(list) = raw else { throw Fault.wrongType(field.name) }
            var result: [String] = []
            for item in list {
                guard case let .string(text) = item else { throw Fault.wrongType(field.name) }
                guard Limits.prefillKeys.contains(text) else { throw Fault.notAllowed(field.name) }
                result.append(text)
            }
            return .stringList(result)
        case .objectList:
            guard case let .array(list) = raw else { throw Fault.wrongType(field.name) }
            var result: [[String: Value]] = []
            var seen = Set<String>()
            for item in list {
                guard case let .object(object) = item else { throw Fault.wrongType(field.name) }
                let validated = try validate(fields: field.items, in: object)
                if let unique = field.uniqueBy, case let .string(key)? = validated[unique],
                   !seen.insert(key).inserted
                {
                    throw Fault.duplicate(field.name)
                }
                result.append(validated)
            }
            return .objectList(result)
        }
    }

    private static func checkString(_ text: String, _ field: Field) throws {
        typealias Fault = BridgeRejection.Fault
        if let maxLength = field.maxLength, text.unicodeScalars.count > maxLength {
            throw Fault.tooLong(field.name)
        }
        if let enumValues = field.enumValues, !enumValues.contains(text) {
            throw Fault.notAllowed(field.name)
        }
        if let pattern = field.pattern, !matches(text, pattern) {
            throw Fault.badFormat(field.name)
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [.anchored], range: range)?.range == range
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

// MARK: - Typed construction

private extension RuntimeMessage {
    /// Builds the typed message from values the table has already validated.
    static func make(_ type: String, _ values: [String: LeadFormBridge.Value]) -> RuntimeMessage {
        func string(_ key: String) -> String {
            if case let .string(value)? = values[key] {
                return value
            }
            return ""
        }
        func code(_ key: String) -> LeadFormErrorCode {
            LeadFormErrorCode(rawValue: string(key)) ?? .temporaryFailure
        }
        func flag(_ key: String) -> Bool {
            if case let .bool(value)? = values[key] {
                return value
            }
            return false
        }
        switch type {
        case "bridge_ready":
            return .bridgeReady(runtimeVersion: string("runtimeVersion"), bridgeVersion: string("bridgeVersion"))
        case "prepared":
            return .prepared(preparedVersionId: string("preparedVersionId"))
        case "activated":
            var keys: [StandardAttributeKey] = []
            if case let .stringList(list)? = values["requestedAttributeKeys"] {
                for item in list {
                    if let key = StandardAttributeKey(rawValue: item), !keys.contains(key) {
                        keys.append(key)
                    }
                }
            }
            var events: [LeadFormEvent: URL] = [:]
            if case let .objectList(list)? = values["events"] {
                for entry in list {
                    if case let .string(name)? = entry["name"], let event = LeadFormEvent(rawValue: name),
                       case let .url(url)? = entry["url"]
                    {
                        events[event] = url
                    }
                }
            }
            return .activated(formVersionId: string("formVersionId"), requestedAttributeKeys: keys, events: events)
        case "prefill_applied": return .prefillApplied
        case "prepare_failed": return .prepareFailed(code: code("errorCode"), retryable: flag("retryable"))
        case "fatal_error": return .fatalError(code: code("errorCode"))
        case "request_close": return .requestClose
        case "request_external_url":
            if case let .url(url)? = values["url"] {
                return .requestExternalURL(
                    purpose: ExternalURLPurpose(rawValue: string("purpose")) ?? .privacyPolicy,
                    url: url
                )
            }
            return .requestClose
        case "event": return .event(name: LeadFormEvent(rawValue: string("name")) ?? .formOpen)
        case "submitting": return .submitting
        case "submit_failed": return .submitFailed(code: code("errorCode"), retryable: flag("retryable"))
        default:
            if case let .date(date)? = values["submittedAt"] {
                return .submitted(leadId: string("leadId"), submittedAt: date)
            }
            return .submitted(leadId: string("leadId"), submittedAt: Date(timeIntervalSince1970: 0))
        }
    }
}
