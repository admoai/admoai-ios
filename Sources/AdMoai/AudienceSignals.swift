import Foundation

/// Standard audience dimensions a publisher can describe a viewer with.
///
/// Each dimension is sent as a custom targeting entry under a fixed wire key, and every value
/// is sent verbatim: the SDK never maps, trims or lower-cases it. Audience dimensions require
/// `SDKConfig.apiVersion` `"2025-11-01"`.
///
/// Publisher segments (``Key/publisherSegments``) are codes the publisher registers with
/// AdMoai; the engine owns that registration. Unknown codes are rejected server-side, and
/// archived codes are still accepted.
public enum AudienceSignals {
    /// The wire keys of the standard audience dimensions, sent verbatim as custom targeting keys.
    public enum Key: String, Sendable, CaseIterable {
        case ageGroup = "age_group"
        case gender
        case accountType = "account_type"
        case subscriptionStatus = "subscription_status"
        case accountTenure = "account_tenure"
        case tripFrequency30d = "trip_frequency_30d"
        case lastTripRecency = "last_trip_recency"
        case publisherSegments = "publisher_segments"
    }

    /// The viewer's age bracket.
    ///
    /// Sent verbatim as the value of the `age_group` custom targeting key.
    public enum AgeGroup: String, Sendable, CaseIterable {
        case under18 = "under_18"
        case age18To24 = "18_24"
        case age25To34 = "25_34"
        case age35To44 = "35_44"
        case age45To54 = "45_54"
        case age55To64 = "55_64"
        case age65Plus = "65_plus"
    }

    /// The viewer's gender as the viewer shared it.
    ///
    /// Sent verbatim as the value of the `gender` custom targeting key.
    public enum Gender: String, Sendable, CaseIterable {
        case female
        case male
        case other
        case preferNotToSay = "prefer_not_to_say"
    }

    /// The kind of account the viewer holds.
    ///
    /// Sent verbatim as the value of the `account_type` custom targeting key.
    public enum AccountType: String, Sendable, CaseIterable {
        case personal
        case business
        case family
        case student
        case other
    }

    /// The viewer's subscription state.
    ///
    /// Sent verbatim as the value of the `subscription_status` custom targeting key.
    public enum SubscriptionStatus: String, Sendable, CaseIterable {
        /// The viewer has no subscription. The wire value is `"none"`; the Swift case is not
        /// called `.none` because that collides with `Optional.none` (`setSubscriptionStatus(.none)`
        /// would silently mean "remove the signal").
        case noSubscription = "none"
        case trial
        case active
        case paused
        case expired
    }

    /// How long the viewer's account has existed.
    ///
    /// Sent verbatim as the value of the `account_tenure` custom targeting key.
    public enum AccountTenure: String, Sendable, CaseIterable {
        case days0To30 = "0_30d"
        case days31To90 = "31_90d"
        case days91To365 = "91_365d"
        case days366Plus = "366d_plus"
    }

    /// How many trips the viewer took in the last 30 days.
    ///
    /// Sent verbatim as the value of the `trip_frequency_30d` custom targeting key.
    public enum TripFrequency30d: String, Sendable, CaseIterable {
        case zero = "0"
        case trips1To2 = "1_2"
        case trips3To9 = "3_9"
        case trips10Plus = "10_plus"
    }

    /// How long ago the viewer's last trip was.
    ///
    /// Sent verbatim as the value of the `last_trip_recency` custom targeting key.
    public enum LastTripRecency: String, Sendable, CaseIterable {
        case never
        case days0To7 = "0_7d"
        case days8To30 = "8_30d"
        case days31To90 = "31_90d"
        case days91Plus = "91d_plus"
    }
}

/// The form factor of the device, not of the app window; `other` is a positively identified
/// other device class, never "unknown" (leave the category unset when it is not known).
public enum DeviceCategory: String, Encodable, Sendable, CaseIterable {
    case phone
    case tablet
    case other
}

/// Turns a carrier name into what the engine should see: the trimmed name, or `nil` when it is
/// empty or a placeholder (`--`, `unknown`, `wifi`, `wi-fi`, any case).
func normalizeCarrier(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    switch trimmed.lowercased() {
    case "--", "unknown", "wifi", "wi-fi": return nil
    default: return trimmed
    }
}
