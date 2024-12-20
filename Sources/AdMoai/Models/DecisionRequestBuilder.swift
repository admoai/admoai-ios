import Foundation
import UIKit

public class DecisionRequestBuilder {
    private var placements: [Placement] = []
    private var targeting: Targeting?
    private var user: User?
    private var device: Device?
    private var app: App?
    private var collectAppData: Bool = true
    private var collectDeviceData: Bool = true

    private let appConfig: AppConfig
    private let deviceConfig: DeviceConfig
    private let userConfig: UserConfig

    internal init(
        appConfig: AppConfig,
        deviceConfig: DeviceConfig,
        userConfig: UserConfig
    ) {
        self.appConfig = appConfig
        self.deviceConfig = deviceConfig
        self.userConfig = userConfig

        self.app = App(
            name: appConfig.name,
            version: appConfig.version,
            buildNumber: appConfig.buildNumber,
            identifier: appConfig.identifier,
            language: appConfig.language
        )

        self.device = Device(
            id: deviceConfig.id,
            model: deviceConfig.model,
            manufacturer: deviceConfig.manufacturer,
            os: deviceConfig.os,
            osVersion: deviceConfig.osVersion,
            timezone: deviceConfig.timezone,
            language: deviceConfig.language
        )

        self.user = User(
            id: userConfig.id,
            ip: userConfig.ip,
            timezone: userConfig.timezone,
            consent: userConfig.consent
        )
    }

    // Placement methods
    public func addPlacement(
        key: String,
        count: Int = 1,
        format: Format = .native,
        advertiserId: String? = nil,
        templateId: String? = nil
    ) -> DecisionRequestBuilder {
        let placement = Placement(
            key: key,
            count: count,
            format: format,
            advertiserId: advertiserId,
            templateId: templateId
        )
        placements.append(placement)
        return self
    }

    public func addPlacement(_ placement: Placement) -> DecisionRequestBuilder {
        placements.append(placement)
        return self
    }

    // Targeting methods
    public func setGeoTargeting(_ geoNameIds: [Int]?) -> DecisionRequestBuilder {
        if targeting == nil {
            targeting = Targeting(geo: geoNameIds)
        } else {
            targeting = Targeting(
                geo: geoNameIds,
                location: targeting?.location,
                custom: targeting?.custom
            )
        }
        return self
    }

    public func addGeoTargeting(_ geoNameId: Int) -> DecisionRequestBuilder {
        var currentGeo = targeting?.geo ?? []
        currentGeo.append(geoNameId)
        return setGeoTargeting(currentGeo)
    }

    public func setLocationTargeting(_ locations: [Targeting.LocationCoordinate]?)
        -> DecisionRequestBuilder
    {
        if targeting == nil {
            targeting = Targeting(location: locations)
        } else {
            targeting = Targeting(
                geo: targeting?.geo,
                location: locations,
                custom: targeting?.custom
            )
        }
        return self
    }

    public func addLocationTargeting(latitude: Double, longitude: Double) -> DecisionRequestBuilder
    {
        let coordinate = Targeting.LocationCoordinate(latitude: latitude, longitude: longitude)
        var currentLocations = targeting?.location ?? []
        currentLocations.append(coordinate)
        return setLocationTargeting(currentLocations)
    }

    public func addLocationTargeting(_ location: Targeting.LocationCoordinate)
        -> DecisionRequestBuilder
    {
        var currentLocations = targeting?.location ?? []
        currentLocations.append(location)
        return setLocationTargeting(currentLocations)
    }

    public func setCustomTargeting(_ custom: [Targeting.CustomKeyValue]?) -> DecisionRequestBuilder
    {
        if targeting == nil {
            targeting = Targeting(custom: custom)
        } else {
            targeting = Targeting(
                geo: targeting?.geo,
                location: targeting?.location,
                custom: custom
            )
        }
        return self
    }

    public func addCustomTargeting(key: String, value: AnyCodable) -> DecisionRequestBuilder {
        var currentCustom = targeting?.custom ?? []
        currentCustom.append(Targeting.CustomKeyValue(key: key, value: value))
        return setCustomTargeting(currentCustom)
    }

    public func addCustomTargeting(_ custom: Targeting.CustomKeyValue) -> DecisionRequestBuilder {
        var currentCustom = targeting?.custom ?? []
        currentCustom.append(custom)
        return setCustomTargeting(currentCustom)
    }

    // User methods
    public func setUserId(_ id: String?) -> DecisionRequestBuilder {
        if user == nil {
            user = User(id: id)
        } else {
            user = User(
                id: id,
                ip: user?.ip,
                timezone: user?.timezone,
                consent: user?.consent
            )
        }
        return self
    }

    public func setUserIp(_ ip: String?) -> DecisionRequestBuilder {
        if user == nil {
            user = User(ip: ip)
        } else {
            user = User(
                id: user?.id,
                ip: ip,
                timezone: user?.timezone,
                consent: user?.consent
            )
        }
        return self
    }

    public func setUserTimezone(_ timezone: String?) -> DecisionRequestBuilder {
        if user == nil {
            user = User(timezone: timezone)
        } else {
            user = User(
                id: user?.id,
                ip: user?.ip,
                timezone: timezone,
                consent: user?.consent
            )
        }
        return self
    }

    public func setUserConsent(_ consent: User.Consent?) -> DecisionRequestBuilder {
        if user == nil {
            user = User(consent: consent)
        } else {
            user = User(
                id: user?.id,
                ip: user?.ip,
                timezone: user?.timezone,
                consent: consent
            )
        }
        return self
    }

    public func disableAppCollection() -> DecisionRequestBuilder {
        collectAppData = false
        app = nil
        return self
    }

    public func disableDeviceCollection() -> DecisionRequestBuilder {
        collectDeviceData = false
        device = nil
        return self
    }

    // Build method
    public func build() -> DecisionRequest {
        return DecisionRequest(
            placements: placements,
            targeting: targeting,
            user: user,
            device: collectDeviceData ? device : nil,
            app: collectAppData ? app : nil
        )
    }
}
