Feature: Audience signals are sent as canonical custom targeting
  As a publisher's tech team
  I want typed helpers for the standard audience dimensions, publisher segments, and the device carrier and category
  So that the values my app sends are the exact strings the engine matches on, and a typo is a compile error or a thrown error instead of a silent non-match

  Audience dimensions require apiVersion "2025-11-01". The SDK never collects any of these
  values on its own: the app states them. Values are sent verbatim.

  Scenario: a typed helper sends the canonical string
    When the app sets the trip frequency to "0 trips" using the typed helper
    Then the request carries the custom targeting entry trip_frequency_30d with the JSON string "0"

  Scenario: every typed value matches the catalog
    Then each typed enum offers exactly the wire values of the audience signals catalog, in catalog order
    And the keys are the eight audience dimensions

  Scenario: the segment helper produces one canonical array
    When the app sets the segments airport_commuter, high_value, airport_commuter
    Then the request carries publisher_segments as ["airport_commuter","high_value"]

  Scenario: one segment code is still an array
    When the app sets the single segment high_value
    Then the request carries publisher_segments as ["high_value"]

  Scenario: an empty segment list removes the entry
    Given the app set the segment high_value earlier
    When the app sets an empty segment list
    Then the request carries no publisher_segments entry

  Scenario: an invalid segment setter is not partially applied
    Given the app set the segment high_value earlier
    When the app sets the segments "ok" and " padded"
    Then the call fails with an invalid publisher segment error naming " padded"
    And the request still carries publisher_segments as ["high_value"]
    And "bad-code" and an empty code are rejected too, while "Mixed_Case_1" is accepted verbatim

  Scenario: setting nil removes the segments
    Given the app set the segment "a" and the custom key theme earlier
    When the app sets the segments to nil
    Then the request carries no publisher_segments entry and the theme key is untouched

  Scenario: the latest explicit setter wins between typed and generic
    Given the app set age_group through the generic custom targeting call
    When the app then sets the age group through the typed helper
    Then the request carries the typed value, and the other custom keys are untouched

  Scenario: setting nil removes only that key
    Given the app set the age group and the gender
    When the app sets the age group to nil
    Then the request still carries the gender and no age_group

  Scenario: nothing new set means nothing new sent
    Given a request that uses none of the audience signals or device carrier and category
    Then its JSON contains no carrier and no category

  Scenario: device carrier and category are sent when configured
    When the app configures the device carrier "Example Mobile" and category phone
    Then the device object carries carrier "Example Mobile" and category "phone"

  Scenario: carrier placeholders and whitespace become absence
    When the app configures the carrier "  Example Mobile  "
    Then the device carrier is "Example Mobile"
    When the app configures the carrier "--", "Unknown", "WiFi", "wi-fi" or only whitespace
    Then the device carries no carrier

  Scenario: disabling device collection omits the whole device object
    Given the app configured a carrier and category manually
    When the request builder disables device collection
    Then the request has no device object
