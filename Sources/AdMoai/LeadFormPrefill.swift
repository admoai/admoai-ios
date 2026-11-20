import Foundation

/// Asks the app for the contact values a form requested, within the contract's deadline, and keeps
/// only what the form may receive.
///
/// The values live in memory for the duration of the lookup and in the returned dictionary the
/// caller sends once: nothing here stores, logs or reports them.
enum LeadFormPrefill {
    /// Looks every key up concurrently and returns what arrived before `timeoutMs` elapsed, after
    /// ``sanitize(_:for:)``. A value that arrives later is discarded. Returns early when every key
    /// has answered.
    ///
    /// Returns even when a provider ignores cancellation or never answers: the lookups are not
    /// awaited past the deadline.
    static func lookup(
        keys: Set<StandardAttributeKey>,
        provider: LeadFormValueProvider,
        timeoutMs: Int = LeadFormBridge.Limits.prefillLookupTimeoutMs
    ) async -> [StandardAttributeKey: String] {
        guard !keys.isEmpty else { return [:] }
        let collector = Collector(expected: keys.count)
        return await withCheckedContinuation { continuation in
            collector.start(continuation)
            let lookups = keys.map { key in
                Task {
                    let raw = await provider.value(for: key)
                    collector.record(key, raw)
                }
            }
            let deadline = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(timeoutMs, 0)) * 1_000_000)
                collector.finish()
            }
            collector.onFinish {
                deadline.cancel()
                lookups.forEach { $0.cancel() }
            }
        }
    }

    /// What the form may receive for `key`, or nil: trimmed, not empty, within the bound, and for
    /// `gender` one of the form's options. Formats (an email's shape, a phone's digits) are the
    /// page's to validate.
    static func sanitize(_ raw: String?, for key: StandardAttributeKey) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              trimmed.unicodeScalars.count <= LeadFormBridge.Limits.maxPrefillValueLength
        else { return nil }
        if key == .gender, !LeadFormBridge.Limits.genderOptions.contains(trimmed) {
            return nil
        }
        return trimmed
    }

    /// Gathers results until every key answered or the deadline passed, whichever is first; after
    /// that it accepts nothing. Resumes the caller exactly once.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let expected: Int
        private var received = 0
        private var values: [StandardAttributeKey: String] = [:]
        private var continuation: CheckedContinuation<[StandardAttributeKey: String], Never>?
        private var finished = false
        private var cleanup: (() -> Void)?

        init(expected: Int) {
            self.expected = expected
        }

        func start(_ continuation: CheckedContinuation<[StandardAttributeKey: String], Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func onFinish(_ cleanup: @escaping () -> Void) {
            lock.lock()
            if finished {
                lock.unlock()
                cleanup()
            } else {
                self.cleanup = cleanup
                lock.unlock()
            }
        }

        func record(_ key: StandardAttributeKey, _ raw: String?) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            received += 1
            if let value = LeadFormPrefill.sanitize(raw, for: key) {
                values[key] = value
            }
            let done = received >= expected
            lock.unlock()
            if done {
                finish()
            }
        }

        func finish() {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let result = values
            values = [:]
            let continuation = continuation
            self.continuation = nil
            let cleanup = cleanup
            self.cleanup = nil
            lock.unlock()
            cleanup?()
            continuation?.resume(returning: result)
        }
    }
}
