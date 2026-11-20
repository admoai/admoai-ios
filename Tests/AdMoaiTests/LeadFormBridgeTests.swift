@testable import AdMoai
import Foundation
import Testing

/// The scenarios of `Sources/AdMoai/LeadFormBridge.feature`, one test per scenario, run against the
/// bridge contract vendored in `Fixtures/interactive-experience/`.
struct LeadFormBridgeTests {
    private static let secret = "tok_SECRET_123"

    // MARK: - Fixtures

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/interactive-experience")

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.fixtures.appendingPathComponent(path), encoding: .utf8)
    }

    private func json(_ path: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text(path).utf8))
    }

    private func files(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.appendingPathComponent(directory).path)
            .filter { $0.hasSuffix(".json") }.sorted().map { "\(directory)/\($0)" }
    }

    private struct Identity { let instanceId: String; let channel: String }

    private func identity() throws -> Identity {
        guard case let .object(object) = try json("bridge/context.json"),
              case let .string(instanceId)? = object["instanceId"],
              case let .string(channel)? = object["channel"] else { throw FixtureError.shape }
        return Identity(instanceId: instanceId, channel: channel)
    }

    private enum FixtureError: Error { case shape }

    private func type(ofFixture path: String) throws -> String {
        guard case let .object(object) = try json(path), case let .string(type)? = object["type"] else {
            throw FixtureError.shape
        }
        return type
    }

    private var everyType: Set<String> {
        Set(LeadFormBridge.Limits.rules.map(\.type))
    }

    private var everyEvent: LeadFormBridge.Context {
        LeadFormBridge.Context(activatedEvents: Set(LeadFormEvent.allCases))
    }

    private func incoming(
        _ string: String,
        exchanged: Set<String>? = nil,
        context: LeadFormBridge.Context? = nil
    ) throws -> Result<RuntimeMessage, BridgeRejection> {
        let id = try identity()
        return LeadFormBridge.validateIncoming(
            string, expected: id.instanceId, channel: id.channel,
            exchanged: exchanged ?? everyType, context: context ?? everyEvent
        )
    }

    private func message(
        _ type: String, _ payload: [String: JSONValue] = [:],
        instanceId: String? = nil, channel: String? = nil
    ) throws -> String {
        let id = try identity()
        return try BridgeEnvelope(
            type: type, instanceId: instanceId ?? id.instanceId, channel: channel ?? id.channel, payload: payload
        ).encoded()
    }

    private func outgoing(_ string: String, exchanged: Set<String>? = nil) throws
        -> Result<(LeadFormBridge.Rule, [String: LeadFormBridge.Value]), BridgeRejection>
    {
        let id = try identity()
        return LeadFormBridge.validate(
            string,
            direction: .appToRuntime,
            instanceId: id.instanceId,
            channel: id.channel,
            exchanged: exchanged
        )
    }

    private func isRefused(_ result: Result<some Any, BridgeRejection>) -> BridgeRejection? {
        if case let .failure(rejection) = result {
            return rejection
        }
        return nil
    }

    private let versionId = JSONValue.string("form_version_01KG000000000000000000V002")

    // Scenario 1
    @Test func everyValidMessageFromTheFormIsAccepted() throws {
        let paths = try files(in: "bridge/runtime-to-app")
        #expect(paths.count == 12)
        for path in paths {
            let type = try type(ofFixture: path)
            let rule = try #require(LeadFormBridge.Limits.rule(for: type))
            let exchanged = Set(rule.after)
            let message = try #require(try? incoming(text(path), exchanged: exchanged).get(), "\(path)")
            #expect(message.wireType == type)
        }
        let activated = try incoming(text("bridge/runtime-to-app/activated.json"), exchanged: ["activate"])
        guard case let .success(.activated(version, keys, events)) = activated else {
            Issue.record("activated did not decode")
            return
        }
        #expect(version == "form_version_01KG000000000000000000V003")
        #expect(keys == [.fullName, .email])
        #expect(Set(events.keys) == Set(LeadFormEvent.allCases))
        let submitted = try incoming(text("bridge/runtime-to-app/submitted.json"), exchanged: ["submitting"])
        guard case let .success(.submitted(leadId, at)) = submitted else {
            Issue.record("submitted did not decode")
            return
        }
        #expect(leadId == "lead_01KG000000000000000000W001")
        #expect(at == Date(timeIntervalSince1970: 1_794_495_845))
    }

    // Scenario 2
    @Test func everyInvalidMessageFromTheFormIsRefused() throws {
        let paths = try files(in: "bridge/invalid/runtime-to-app")
        #expect(paths.count == 10)
        for path in paths {
            // Every predecessor is satisfied, so the refusal is about the message itself.
            let result = try incoming(text(path), exchanged: everyType)
            #expect(isRefused(result) != nil, "\(path) must be refused")
        }
    }

    // Scenario 3
    @Test func whatTheSDKSendsIsWhatTheContractShows() throws {
        let id = try identity()
        let token = "REDACTED_PREPARATION_TOKEN"
        let expected: [String: AppMessage] = [
            "activate": .activate,
            "back": .back,
            "became-hidden": .becameHidden,
            "became-visible": .becameVisible,
            "dispose": .dispose,
            "initialize-inline": .initialize(preparationToken: token, presentation: .inline),
            "initialize": .initialize(preparationToken: token, presentation: .fullScreen),
            "prefill": .prefill(values: [.fullName: "Alex Morgan", .email: "alex@example.invalid"]),
            "retry-prepare": .retryPrepare,
        ]
        let paths = try files(in: "bridge/app-to-runtime")
        #expect(paths.count == expected.count)
        for path in paths {
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".json", with: "")
            let message = try #require(expected[name], "\(name)")
            let encoded = try message.encode(instanceId: id.instanceId, channel: id.channel)
            #expect(try JSONDecoder().decode(JSONValue.self, from: Data(encoded.utf8)) == json(path), "\(name)")
            #expect(try isRefused(outgoing(text(path))) == nil, "\(name) validates as an app message")
        }
    }

    // Scenario 4
    @Test func theSDKCannotSendWhatTheContractForbids() throws {
        let id = try identity()
        func encode(_ message: AppMessage, allowed: Set<StandardAttributeKey>? = nil) throws -> String {
            try message.encode(instanceId: id.instanceId, channel: id.channel, allowedPrefillKeys: allowed)
        }
        #expect(throws: BridgeRejection.self) { try encode(.prefill(values: [.fullName: String(
            repeating: "A",
            count: 257
        )])) }
        _ = try encode(.prefill(values: [.fullName: String(repeating: "A", count: 256)]))
        #expect(throws: BridgeRejection.self) { try encode(.prefill(values: [.fullName: "x"]), allowed: [.email]) }
        _ = try encode(.prefill(values: [.email: "x"]), allowed: [.email])
        #expect(throws: BridgeRejection.self) { try encode(.prefill(values: [.gender: "robot"])) }
        for gender in ["female", "male", "other", "prefer_not_to_say"] {
            _ = try encode(.prefill(values: [.gender: gender]))
        }
        #expect(throws: BridgeRejection.self) {
            try encode(.initialize(preparationToken: String(repeating: "t", count: 4097), presentation: .inline))
        }
        #expect(StandardAttributeKey(rawValue: "homeAddress") == nil)
        #expect(LeadFormPresentation(rawValue: "modal") == nil)
        // back-before-visible has a valid shape and is refused by order: only these were exchanged.
        let beforeVisible: Set = [
            "bridge_ready", "initialize", "prepared", "activate", "activated", "prefill", "prefill_applied",
        ]
        for path in try files(in: "bridge/invalid/app-to-runtime") {
            let exchanged = path.hasSuffix("back-before-visible.json") ? beforeVisible : nil
            #expect(try isRefused(outgoing(text(path), exchanged: exchanged)) != nil, "\(path) must be refused")
        }
        let back = try text("bridge/app-to-runtime/back.json")
        #expect(try isRefused(outgoing(back, exchanged: beforeVisible)) == .outOfOrder(type: "back"))
        #expect(try isRefused(outgoing(back, exchanged: beforeVisible.union(["became_visible"]))) == nil)
    }

    // Scenario 5
    @Test func aMessageFromTheAppsOwnDirectionIsRefusedAsIncoming() throws {
        for path in try files(in: "bridge/app-to-runtime") {
            let type = try type(ofFixture: path)
            #expect(try isRefused(incoming(text(path))) == .wrongDirection(type: type), "\(path)")
        }
    }

    // Scenario 6
    @Test func identityIsCheckedOnEveryMessage() throws {
        let payload = ["preparedVersionId": versionId]
        #expect(try isRefused(incoming(text("bridge/invalid/runtime-to-app/wrong-channel.json"))) == .wrongChannel)
        #expect(try isRefused(incoming(message("prepared", payload, channel: "chan_example_0000000002"))) ==
            .wrongChannel)
        #expect(try isRefused(incoming(message(
            "prepared",
            payload,
            instanceId: "form_instance_01KG000000000000000000N999"
        )))
            == .wrongInstance)
        #expect(try isRefused(incoming(message("prepared", payload))) == nil)
    }

    // Scenario 7
    @Test func orderIsEnforced() throws {
        let prepared = try message("prepared", ["preparedVersionId": versionId])
        #expect(try isRefused(incoming(prepared, exchanged: [])) == .outOfOrder(type: "prepared"))
        #expect(try isRefused(incoming(prepared, exchanged: ["initialize"])) == nil)
        #expect(try isRefused(incoming(prepared, exchanged: ["retry_prepare"])) == nil)
        let submitted = try text("bridge/runtime-to-app/submitted.json")
        #expect(try isRefused(incoming(submitted, exchanged: ["became_visible"])) == .outOfOrder(type: "submitted"))
        #expect(try isRefused(incoming(submitted, exchanged: ["submitting"])) == nil)
        #expect(try isRefused(incoming(message("request_close"), exchanged: [])) == .outOfOrder(type: "request_close"))

        let website = try message(
            "request_external_url",
            ["purpose": .string("website_cta"), "url": .string("https://a.example.invalid/")]
        )
        let privacy = try message(
            "request_external_url",
            ["purpose": .string("privacy_policy"), "url": .string("https://a.example.invalid/")]
        )
        #expect(try isRefused(incoming(website, exchanged: ["became_visible"])) ==
            .notAllowedNow(type: "request_external_url"))
        #expect(try isRefused(incoming(website, exchanged: ["became_visible", "submitted"])) == nil)
        #expect(try isRefused(incoming(privacy, exchanged: ["became_visible"])) == nil)

        // Every error the submissions request can answer ends the announced submission.
        for code in [LeadFormErrorCode.unauthorized, .formNotAvailable, .invalidRequest] {
            let failed = try message("submit_failed", ["errorCode": .string(code.rawValue), "retryable": .bool(false)])
            #expect(try incoming(failed, exchanged: ["submitting"]).get() ==
                .submitFailed(code: code, retryable: false))
            #expect(!code.isRetryable)
        }

        let event = try message("event", ["name": .string("form_start")])
        let listed = LeadFormBridge.Context(activatedEvents: [.formOpen])
        #expect(try isRefused(incoming(event, exchanged: ["became_visible"], context: listed)) ==
            .notAllowedNow(type: "event"))
        #expect(try isRefused(incoming(event, exchanged: ["became_visible"], context: everyEvent)) == nil)
    }

    // Scenario 8
    @Test func sizeAndShapeAreBounded() throws {
        #expect(LeadFormBridge.Limits.maxMessageBytes == 16384)
        #expect(try isRefused(incoming(text("bridge/invalid/runtime-to-app/oversized-message.json"))) == .oversize)
        let padded = try message("request_close").dropLast() + ",\"x\":\"\(String(repeating: "a", count: 16384))\"}"
        #expect(try isRefused(incoming(String(padded))) == .oversize)
        #expect(try isRefused(incoming("not json")) == .notJSON)
        #expect(try isRefused(incoming("[1,2]")) == .malformedEnvelope)
        let id = try identity()
        let extraEnvelopeKey = "{\"type\":\"request_close\",\"instanceId\":\"\(id.instanceId)\",\"channel\":\"\(id.channel)\",\"payload\":{},\"x\":1}"
        #expect(try isRefused(incoming(extraEnvelopeKey)) == .malformedEnvelope)
        #expect(try isRefused(incoming(message("request_close", ["x": .string("y")])))
            == .invalidPayload(type: "request_close", fault: .unknownField))
        #expect(try isRefused(incoming(message(
            "prepare_failed",
            ["errorCode": .string("expired"), "retryable": .number(1)]
        )))
            == .invalidPayload(type: "prepare_failed", fault: .wrongType("retryable")))
        #expect(try isRefused(incoming(message("unheard_of"))) == .unknownType)
    }

    // Scenario 9
    @Test func aPageThatSpeaksAnotherBridgeVersionIsRefused() throws {
        let unknown = try isRefused(incoming(text("bridge/invalid/runtime-to-app/unknown-bridge-version.json")))
        #expect(unknown?.isUnsupportedBridgeVersion == true)
        let missing = try isRefused(incoming(message("bridge_ready", ["runtimeVersion": .string("1.0.0")])))
        #expect(missing == .invalidPayload(type: "bridge_ready", fault: .missingField("bridgeVersion")))
        #expect(missing?.isUnsupportedBridgeVersion == false)
        #expect(try isRefused(incoming(text("bridge/runtime-to-app/bridge-ready.json"))) == nil)
        #expect(LeadFormBridge.Limits.bridgeVersions == ["1"])
    }

    // Scenario 10
    @Test func hostileTextRoundTripsExactly() throws {
        let id = try identity()
        let hostile = "He said \"hi\" </script><script>alert(1)</script>\nline2\r\n\u{2028}tab\t 日本語 😀 \\ 'x' é"
        let encoded = try AppMessage.prefill(values: [.fullName: hostile]).encode(
            instanceId: id.instanceId,
            channel: id.channel
        )
        let envelope = try BridgeEnvelope.decode(encoded).get()
        guard case let .object(values)? = envelope.payload["values"],
              case let .string(back)? = values["fullName"]
        else {
            Issue.record("no values")
            return
        }
        #expect(back == hostile)
        #expect(!encoded.contains("\n"), "the JSON text itself is one line")
    }

    // Scenario 11
    @Test func aRefusalNeverContainsTheTokenOrAValue() throws {
        let id = try identity()
        let s = Self.secret
        let hostileMessages = try [
            message(s), // unknown type
            message("request_close", [s: .string(s)]), // unknown field named like the token
            message("event", ["name": .string(s)]),
            message("prepared", ["preparedVersionId": .string(s)]),
            message("bridge_ready", ["runtimeVersion": .string(s), "bridgeVersion": .string(s)]),
            message("fatal_error", ["errorCode": .string(s)]),
            message("request_close", instanceId: s),
            message("request_close", channel: s),
            "{\"type\":\"\(s)\"",
            s,
        ]
        for text in hostileMessages {
            let rejection = try #require(isRefused(incoming(text)), "\(text)")
            for output in [rejection.description, String(describing: rejection), String(reflecting: rejection)] {
                #expect(!output.contains(s), "\(output)")
            }
        }
        let initialize = AppMessage.initialize(preparationToken: s, presentation: .inline)
        let prefill = AppMessage.prefill(values: [.email: s])
        for message in [initialize, prefill] {
            var dumped = ""
            dump(message, to: &dumped)
            for output in [message.description, String(describing: message), String(reflecting: message), dumped] {
                #expect(!output.contains(s), "\(output)")
            }
        }
        let tooLong = AppMessage.prefill(values: [.fullName: s + String(repeating: "A", count: 300)])
        do {
            _ = try tooLong.encode(instanceId: id.instanceId, channel: id.channel)
            Issue.record("must refuse")
        } catch {
            #expect(!String(describing: error).contains(s))
        }
    }

    // Scenario 12
    @Test func theSDKsTableEqualsTheContract() throws {
        guard case let .object(contract) = try json("bridge-messages.json") else { throw FixtureError.shape }
        func number(_ key: String) -> Int? {
            if case let .number(value)? = contract[key] {
                return Int(value)
            }
            return nil
        }
        #expect(number("maxMessageBytes") == LeadFormBridge.Limits.maxMessageBytes)
        #expect(number("maxHiddenPreparedForms") == LeadFormBridge.Limits.maxHiddenPreparedForms)
        #expect(number("prefillLookupTimeoutMs") == LeadFormBridge.Limits.prefillLookupTimeoutMs)

        guard case let .object(envelope)? = contract["envelope"],
              case let .object(instance)? = envelope["instanceId"],
              case let .string(instancePattern)? = instance["pattern"],
              case let .object(channel)? = envelope["channel"], case let .string(channelPattern)? = channel["pattern"]
        else { throw FixtureError.shape }
        #expect(instancePattern == LeadFormBridge.Limits.instanceIdPattern)
        #expect(channelPattern == LeadFormBridge.Limits.channelPattern)

        guard case let .array(messages)? = contract["messages"] else { throw FixtureError.shape }
        let swiftRules = LeadFormBridge.Limits.rules
        #expect(messages.count == swiftRules.count)
        for (index, wire) in messages.enumerated() where index < swiftRules.count {
            let rule = swiftRules[index]
            #expect(Self.strippingDescriptions(wire) == Self.render(rule), "message \(rule.type)")
        }

        // The vocabulary the typed enums carry is the contract's.
        guard case let .object(standard) = try json("standard-fields.json"),
              case let .array(prefill)? = standard["prefillKeys"],
              case let .array(genders)? = standard["genderOptions"] else { throw FixtureError.shape }
        #expect(prefill == StandardAttributeKey.allCases.map { .string($0.rawValue) })
        let genderValues: [JSONValue] = genders.compactMap {
            if case let .object(option) = $0 {
                return option["value"]
            }
            return nil
        }
        #expect(genderValues == LeadFormBridge.Limits.genderOptions.map { .string($0) })
        guard case let .object(codes) = try json("error-codes.json"), case let .array(list)? = codes["codes"] else {
            throw FixtureError.shape
        }
        let keys: Set<String> = Set(list.compactMap {
            if case let .object(code) = $0, case let .string(key)? = code["key"] {
                return key
            }
            return nil
        })
        #expect(Set(LeadFormErrorCode.allCases.map(\.rawValue)).isSubset(of: keys))
        // Retryability per code is the contract's.
        for entry in list {
            guard case let .object(code) = entry, case let .string(key)? = code["key"],
                  case let .bool(retryable)? = code["retryable"],
                  let known = LeadFormErrorCode(rawValue: key) else { continue }
            #expect(known.isRetryable == retryable, "\(key)")
        }
    }

    // MARK: - Contract rendering

    private static func strippingDescriptions(_ value: JSONValue) -> JSONValue {
        switch value {
        case let .object(object):
            .object(object.filter { $0.key != "description" }.mapValues(strippingDescriptions))
        case let .array(list):
            .array(list.map(strippingDescriptions))
        default:
            value
        }
    }

    private static func render(_ rule: LeadFormBridge.Rule) -> JSONValue {
        .object([
            "type": .string(rule.type),
            "direction": .string(rule.direction.rawValue),
            "after": .array(rule.after.map { .string($0) }),
            "payload": .object(Dictionary(uniqueKeysWithValues: rule.fields.map { ($0.name, render($0)) })),
        ])
    }

    private static func render(_ field: LeadFormBridge.Field) -> JSONValue {
        var object: [String: JSONValue] = ["type": .string(field.kind.rawValue), "required": .bool(field.required)]
        if let values = field.enumValues {
            object["enum"] = .array(values.map { .string($0) })
        }
        if let pattern = field.pattern {
            object["pattern"] = .string(pattern)
        }
        if let maxLength = field.maxLength {
            object["maxLength"] = .number(Double(maxLength))
        }
        if field.fromPrefillKeys {
            object[field.kind == .stringMap ? "keysFrom" : "itemsFrom"] = .string("prefillKeys")
        }
        if let unique = field.uniqueBy {
            object["uniqueBy"] = .string(unique)
        }
        if !field.items.isEmpty {
            object["items"] = .object(Dictionary(uniqueKeysWithValues: field.items.map { ($0.name, render($0)) }))
        }
        return .object(object)
    }
}
