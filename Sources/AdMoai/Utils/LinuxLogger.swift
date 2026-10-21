#if !canImport(OSLog)
    import Foundation

    /// A stand-in for `os.Logger` where OSLog does not exist (Linux).
    ///
    /// The SDK ships on Apple platforms only, but its black-box E2E runner (`journey-e2e`) runs in
    /// adhub's CI on Linux against a mock-seeded engine (admoai/adhub#4346). This keeps the SDK
    /// source identical on both: the same `Logger(subsystem:category:)` initializer, the same
    /// `debug/info/notice/warning/error/fault` calls and the same `\(value, privacy: .public)`
    /// interpolation, written to standard error. It is compiled only when OSLog is unavailable,
    /// so nothing changes on iOS or macOS.
    public struct Logger: Sendable {
        public let subsystem: String
        public let category: String

        public init(subsystem: String, category: String) {
            self.subsystem = subsystem
            self.category = category
        }

        public func debug(_ message: LinuxLogMessage) {
            write("debug", message)
        }

        public func info(_ message: LinuxLogMessage) {
            write("info", message)
        }

        public func notice(_ message: LinuxLogMessage) {
            write("notice", message)
        }

        public func warning(_ message: LinuxLogMessage) {
            write("warning", message)
        }

        public func error(_ message: LinuxLogMessage) {
            write("error", message)
        }

        public func fault(_ message: LinuxLogMessage) {
            write("fault", message)
        }

        private func write(_ level: String, _ message: LinuxLogMessage) {
            FileHandle.standardError.write(Data("[\(category)] \(level): \(message.text)\n".utf8))
        }
    }

    /// `os.Logger`'s privacy marker. On Linux there is no log redaction; it is accepted and ignored.
    public enum LinuxLogPrivacy: Sendable {
        case `public`, `private`, auto, sensitive
    }

    /// The message type `Logger` takes, so `\(value, privacy: .public)` compiles as it does with OSLog.
    public struct LinuxLogMessage: ExpressibleByStringInterpolation, Sendable {
        public let text: String

        public init(stringLiteral value: String) {
            text = value
        }

        public init(stringInterpolation: Interpolation) {
            text = stringInterpolation.text
        }

        public struct Interpolation: StringInterpolationProtocol {
            var text = ""
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ literal: String) {
                text += literal
            }

            public mutating func appendInterpolation<T>(_ value: T, privacy: LinuxLogPrivacy = .auto) {
                text += String(describing: value)
            }
        }
    }
#endif
