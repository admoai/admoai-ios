@_spi(InteractiveExperience) @testable import AdMoai
import Foundation
import Testing

/// The scenarios of `Sources/AdMoai/LeadFormPrefill.feature`, one test per scenario.
struct LeadFormPrefillTests {
    private final class Provider: LeadFormValueProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [StandardAttributeKey] = []
        let values: [StandardAttributeKey: String]
        let delaysMs: [StandardAttributeKey: Int]

        init(_ values: [StandardAttributeKey: String], delaysMs: [StandardAttributeKey: Int] = [:]) {
            self.values = values
            self.delaysMs = delaysMs
        }

        var availableKeys: Set<StandardAttributeKey> {
            Set(values.keys)
        }

        var askedKeys: [StandardAttributeKey] {
            lock.lock()
            defer { lock.unlock() }
            return asked
        }

        func value(for key: StandardAttributeKey) async -> String? {
            lock.lock()
            asked.append(key)
            lock.unlock()
            if let delay = delaysMs[key] {
                // Deliberately ignores cancellation: a provider that does not cooperate.
                var remaining = delay
                while remaining > 0 {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                    remaining -= 10
                }
            }
            return values[key]
        }
    }

    // Scenario 1
    @Test func theAppsValuesReachTheFormOnceWithinTheDeadline() async {
        let provider = Provider([.email: "a@b.co", .phone: "+34123"])
        let result = await LeadFormPrefill.lookup(keys: [.email, .phone], provider: provider, timeoutMs: 1000)
        #expect(result == [.email: "a@b.co", .phone: "+34123"])
        #expect(Set(provider.askedKeys) == [.email, .phone])
        #expect(provider.askedKeys.count == 2)
        #expect(LeadFormBridge.Limits.prefillLookupTimeoutMs == 1500)
    }

    // Scenario 2
    @Test func onlyValuesTheFormMayReceiveAreSent() {
        #expect(LeadFormPrefill.sanitize("   ", for: .firstName) == nil)
        #expect(LeadFormPrefill.sanitize("", for: .firstName) == nil)
        #expect(LeadFormPrefill.sanitize(nil, for: .firstName) == nil)
        #expect(LeadFormPrefill.sanitize(String(repeating: "x", count: 257), for: .lastName) == nil)
        let exact = String(repeating: "x", count: LeadFormBridge.Limits.maxPrefillValueLength)
        #expect(LeadFormPrefill.sanitize(exact, for: .lastName) == exact)
        #expect(LeadFormPrefill.sanitize("  Ana \n", for: .firstName) == "Ana")
        #expect(LeadFormPrefill.sanitize("unicorn", for: .gender) == nil)
        #expect(LeadFormPrefill.sanitize("female", for: .gender) == "female")
        #expect(LeadFormPrefill.sanitize("not-an-email", for: .email) == "not-an-email", "formats are the page's")
    }

    // Scenario 3
    @Test func aLateValueIsDiscarded() async {
        let provider = Provider([.email: "a@b.co", .phone: "+34123"], delaysMs: [.phone: 300])
        let result = await LeadFormPrefill.lookup(keys: [.email, .phone], provider: provider, timeoutMs: 40)
        #expect(result == [.email: "a@b.co"])
        try? await Task.sleep(nanoseconds: 400_000_000)
        #expect(result == [.email: "a@b.co"])
    }

    // Scenario 4
    @Test func waitingStopsAsSoonAsEveryKeyAnswered() async {
        let provider = Provider([.email: "a@b.co", .phone: "+34123"])
        let start = Date()
        let result = await LeadFormPrefill.lookup(keys: [.email, .phone], provider: provider, timeoutMs: 10000)
        #expect(result.count == 2)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    // Scenario 5
    @Test func anAppThatNeverAnswersCannotHoldTheForm() async {
        let provider = Provider([.email: "a@b.co", .phone: "+34123"], delaysMs: [.phone: 5000])
        let start = Date()
        let result = await LeadFormPrefill.lookup(keys: [.email, .phone], provider: provider, timeoutMs: 50)
        #expect(result == [.email: "a@b.co"])
        #expect(Date().timeIntervalSince(start) < 2)
    }

    // Scenario 6
    @Test func nothingIsAskedWhenThereIsNothingToAsk() async {
        let provider = Provider([.phone: "+34123"])
        let result = await LeadFormPrefill.lookup(keys: [], provider: provider, timeoutMs: 50)
        #expect(result.isEmpty)
        #expect(provider.askedKeys.isEmpty)
    }
}
