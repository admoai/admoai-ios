# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0](https://github.com/admoai/admoai-ios/admoai/admoai-ios/compare/0.1.0...v1.1.0) (2025-12-11)


### Added

* add clear methods to DecisionRequestBuilder ([d16b83d](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/d16b83d99727ac859e3fb854b67bf22f9d3fcdad))
* add default parameter to fireClick method in AdMoai struct ([4ef9972](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/4ef99728a300cb29f3374ec54379daa04ce94019))
* enhance DeviceDetails to support macOS and improve optional handling for device information ([4c96ca5](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/4c96ca564f17d90f268f53993f728eb78599bd36))
* enhance targeting pickers with improved UI and functionality ([645777e](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/645777eaed79dfe537ef17652113d0b40d055e2d))
* expand DecisionRequestTests with comprehensive location and custom targeting scenarios ([aafb1eb](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/aafb1eba0c21235b94e6264cb7cee8b9426d9248))
* initial release of AdMoai iOS SDK with comprehensive features and documentation ([#1](https://github.com/admoai/admoai-ios/admoai/admoai-ios/issues/1)) ([edc59da](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/edc59da0b0c5c1e1d33e739119d7eca091f24e47))
* simplify Targeting struct and enhance DecisionRequestBuilder for unique location and custom targeting ([9bd0595](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/9bd05951ccd6dada097c52594f543181eb400f50))
* update AdMoaiTests to use secure base URL and add default config tests ([ac58f77](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/ac58f7783b752c12633fe9a3a753be5e4239c801))


### Fixed

* update base URL in DecisionRequestTests to use mock endpoint ([3bbfc48](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/3bbfc48eab85ba534fc4b7d72cca0340fddcbfc1))


### Changed

* change access level of value property in AnyCodable struct ([0cc9fc3](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/0cc9fc3aae99ce92708c67f89f0e837ccc0e5791))
* make sdk property public in ContentViewModel and update tracking logic in TrackingItemView ([695fd76](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/695fd768f1cec0054690ecaf5326abb62ee718d7))
* rename files ([f195f8c](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/f195f8c6c6cd03a3b19c128681d7abaf8fe24aa8))
* update AppDetails struct to make name, version, buildNumber, and identifier optional ([bc83d9d](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/bc83d9de9d5fc990566ec1e687a7771bd374036c))
* update HTTPRequestView to use correct path and headers for API request preview ([29b4f10](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/29b4f10131bda5e65d78c8e205dc8d1a8562aeea))
* update method signature for addCustomTargeting in DecisionRequestBuilder ([bb1493f](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/bb1493f968955b6c08a079bebfbe7428f09d99e7))


### Documentation

* generate SDK documentation for GitHub Pages ([d3d81ea](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/d3d81ea6ce6f47a36150b8164077a23e67106687))
* update docs ([1a80d68](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/1a80d68882d301522e92c39b57928ce0fb2e8b13))
* update README.md to include custom targeting example and logout cleanup instructions ([584ef84](https://github.com/admoai/admoai-ios/admoai/admoai-ios/commit/584ef84afd659fe9b8b19af59514e27b8d64f241))

## [0.1.0] - 2024-11-01

### Added
- Initial release of AdMoai iOS SDK
- Ad request and decision API with `DecisionRequestBuilder`
- Support for targeting (location, demographics, interests, custom attributes)
- Real-time ad tracking (impressions, clicks, custom events)
- Swift Package Manager support
- Configuration management (user, app, and SDK configs)
- Error handling with structured exception types
- SwiftUI and UIKit compatibility
- Demo application demonstrating SDK integration
- Comprehensive documentation with DocC

### Technical Details
- **Minimum iOS**: 14.0
- **Minimum macOS**: 11.0
- **Swift Version**: 5.9+
- **Supported Platforms**: iOS, macOS
- **Package Manager**: Swift Package Manager
- **Architecture**: Modern Swift with async/await support

[0.1.0]: https://github.com/admoai/admoai-ios/releases/tag/v0.1.0
