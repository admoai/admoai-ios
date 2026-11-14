Feature: The device category is collected from the platform once the app opts in, the carrier never is
  As a publisher's tech team
  I want the SDK to fill the device category on its own when I enable it, and leave the carrier to me
  So that ads can target phones and tablets without my app stating it, an upgrade never changes what my app sends, and nothing the platform cannot vouch for is sent as fact

  Collection is opt-in: a workspace whose audience-signals contract is off refuses device.category,
  so an app that only upgrades the SDK keeps sending exactly what it sent before.

  The hardware class decides first: an app on Mac hardware (an iOS app on a Mac, or a Mac Catalyst app) is other, whatever idiom it reports.
  Otherwise the user-interface idiom the system reports decides: phone idiom is phone, pad idiom is
  tablet, Mac, TV, CarPlay and Vision are other, and an unspecified idiom leaves the category
  absent (no reliable classification is never reported as other). An iPhone-only app running on an
  iPad reports the phone idiom, so it is phone. Neither the hardware class nor the idiom can change
  while the process runs, so the platform is read once, and a value the app states wins over the collected one. On modern iOS the carrier is not reliably available (Apple's
  CTCarrier returns static values and describes the home provider, not the current operator),
  so it is never collected automatically; the app can still state it.

  Scenario: a phone idiom is a phone
    When the host reports the phone idiom
    Then the device category is phone

  Scenario: a pad idiom is a tablet
    When the host reports the pad idiom
    Then the device category is tablet

  Scenario: an iPhone-only app on an iPad is a phone
    When an iPhone-only app runs on an iPad and the host reports the phone idiom
    Then the device category is phone

  Scenario: every other known idiom is other
    When the host reports the mac, tv, carPlay or vision idiom
    Then the device category is other

  Scenario: an unspecified idiom leaves the category absent
    When the host reports the unspecified idiom
    Then the device category is absent

  Scenario: an iOS app on a Mac is other even with the pad idiom
    When an iOS app runs on a Mac and the host reports the pad idiom
    Then the device category is other

  Scenario: a Mac Catalyst app is other even with the pad idiom
    When a Mac Catalyst app runs and the host reports the pad idiom
    Then the device category is other

  Scenario: the default SDK sends no device category
    Given the app did not enable device-category collection
    When a request is built
    Then the request carries no device category, whatever the platform reports
    And resetting the device configuration does not start collection

  Scenario: enabling collection sends the platform category
    When the app enables device-category collection
    Then the request carries the category the platform reports

  Scenario: modern iOS has no reliable automatic carrier
    When the SDK collects the system device configuration
    Then the carrier is absent while the other device fields are still present

  Scenario: clearing the device configuration stops collection
    Given the app enabled device-category collection
    When the app clears the device configuration
    Then a request built afterwards carries no device category

  Scenario: resetting the device configuration collects again
    Given the app enabled device-category collection and then cleared the device configuration
    When the app resets the device configuration
    Then a request built afterwards carries the system device category

  Scenario: a manual category overrides the system value
    Given the app did not enable device-category collection
    When the app sets the device category to tablet
    Then the request carries the device category tablet

  Scenario: a manual category wins over the collected one
    Given the host reports the phone idiom
    When the app sets the device category to tablet
    Then the request carries the device category tablet

  Scenario: a manual category removed by the app stays absent
    Given the host reports the phone idiom
    And the app set the device category to tablet
    When the app sets the device category to nil
    Then the request carries no device category, not the collected phone
    And after the app resets the device configuration the collected category phone is sent again

  Scenario: the platform is read once per process
    When the SDK classifies the device for several requests
    Then the hardware class and the idiom are read once, on first use, and every later request reuses them

  Scenario: disabling device collection omits the device object
    When the app disables device collection on a request
    Then the request carries no device object, category included

  Scenario: disabling app collection keeps the device category
    Given the app enabled device-category collection
    When the app disables app collection on a request
    Then the request still carries the device category
