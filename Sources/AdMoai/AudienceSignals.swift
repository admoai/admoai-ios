import Foundation

/// Standard audience dimensions a publisher can describe a viewer with.
///
/// Each dimension is sent as a custom targeting entry under a fixed wire key, and every value
/// is sent verbatim: the SDK never maps, trims or lower-cases it. The engine validates and
/// matches the values on every decision version; reporting by audience requires
/// `SDKConfig.apiVersion` `"2025-11-01"`.
///
/// Compute each value from facts the app holds about the viewer, and leave a dimension unset
/// when the fact is unknown: the SDK and the engine never derive one value from another.
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
        case activityFrequency30d = "activity_frequency_30d"
        case lastActivityRecency = "last_activity_recency"
        case publisherSegments = "publisher_segments"
    }

    /// The viewer's age bracket, in completed years at the time of the request. `under18` is
    /// below 18, each numbered bracket includes both its end ages, and `age65Plus` starts at 65.
    /// Unknown age: leave it unset.
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

    /// The viewer's gender as the viewer stated it in their profile. `other` is a stated gender
    /// outside `female` and `male`; `preferNotToSay` is a choice the viewer recorded, never a
    /// default for missing data.
    ///
    /// Sent verbatim as the value of the `gender` custom targeting key.
    public enum Gender: String, Sendable, CaseIterable {
        case female
        case male
        case other
        case preferNotToSay = "prefer_not_to_say"
    }

    /// The type of the profile in use, not every membership the viewer holds. `other` is a known
    /// type outside the four named ones; unknown: leave it unset.
    ///
    /// Sent verbatim as the value of the `account_type` custom targeting key.
    public enum AccountType: String, Sendable, CaseIterable {
        case personal
        case business
        case family
        case student
        case other
    }

    /// The state of the viewer's one relevant current subscription or pass. Leave it unset when
    /// no single relevant subscription exists.
    ///
    /// Sent verbatim as the value of the `subscription_status` custom targeting key.
    public enum SubscriptionStatus: String, Sendable, CaseIterable {
        /// Known to have no current or previous relevant subscription (not "unknown"). The wire
        /// value is `"none"`; the Swift case is not
        /// called `.none` because that collides with `Optional.none` (`setSubscriptionStatus(.none)`
        /// would silently mean "remove the signal").
        case noSubscription = "none"
        case trial
        case active
        case paused
        case expired
    }

    /// The age of the viewer's account with the publisher's service, not of the app installation,
    /// in elapsed days: completed 24-hour periods between UTC instants, `floor(seconds / 86400)`,
    /// with day 0 at the account's creation.
    ///
    /// Sent verbatim as the value of the `account_tenure` custom targeting key.
    public enum AccountTenure: String, Sendable, CaseIterable {
        case days0To30 = "0_30d"
        case days31To90 = "31_90d"
        case days91To365 = "91_365d"
        case days366Plus = "366d_plus"
    }

    /// Completed activities in the 30 × 24 hours before the request. An activity is one completed
    /// use of the service (a ride, a parking session, a ticket, a rental); a booking, a cancelled
    /// or a failed use does not count. `zero` means none are known to have happened.
    ///
    /// Sent verbatim as the value of the `activity_frequency_30d` custom targeting key.
    public enum ActivityFrequency30d: String, Sendable, CaseIterable {
        case zero = "0"
        case times1To2 = "1_2"
        case times3To9 = "3_9"
        case times10Plus = "10_plus"
    }

    /// Elapsed days since the viewer's latest completed activity (completed 24-hour periods
    /// between UTC instants). `never` means the viewer is known never to have completed one.
    ///
    /// Sent verbatim as the value of the `last_activity_recency` custom targeting key.
    public enum LastActivityRecency: String, Sendable, CaseIterable {
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
