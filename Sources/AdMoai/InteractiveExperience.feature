Feature: Interactive experiences are opt-in and decoded safely
  As a publisher's tech team
  I want to opt in to Lead Generation forms explicitly, and have the SDK declare only the names of the contact values my app holds
  So that an SDK update never changes what my viewers are shown, no personal value leaves the app before a viewer opens a form, and an unusable form never breaks my ad response

  The contract is vendored in Tests/AdMoaiTests/Fixtures/interactive-experience/. The SDK never
  reads a contact value when it builds a request. Lead Generation is served only on API version
  "2025-11-01".

  Scenario: An SDK update alone does not declare support
    Given the app never opted in to interactive experiences
    When the app builds a decision request
    Then the request has no interactiveExperience extension

  Scenario: An opted-in app declares the keys it holds, never the values
    Given the app opted in with a provider holding email, fullName and phone
    When the app builds a decision request
    Then the interactiveExperience extension is the one in request-supported-with-keys.json
    And the provider was asked once for its key names, and the protocol offers no way to ask for a value

  Scenario: An opted-in app with no values still declares support
    Given the app opted in with a provider holding no values
    When the app builds a decision request
    Then the interactiveExperience extension is the one in request-supported-empty-keys.json

  Scenario: Keys are read when each request is built
    Given the app opted in with a provider holding email
    When the app builds a request, the provider then holds phone, and the app builds another
    Then each request carries the keys the provider held when it was built

  Scenario: Opting out stops declaring
    Given the app opted in and then opted out
    When the app builds a decision request
    Then the request has no interactiveExperience extension

  Scenario: A platform without a secure form view declares nothing
    Given the app opted in on a platform without a secure form view
    When the app builds a decision request
    Then the request has no interactiveExperience extension
    And interactive experiences are reported as not enabled

  Scenario: Every copy of the SDK shares the opt-in
    Given the app opted in on one copy of the SDK
    When the app builds a decision request from another copy
    Then the request declares support

  Scenario: The typed keys are the contract's
    Then the typed contact keys are the contract's prefill keys, in order
    And they are the contract's standard fields, in order

  Scenario: A Lead Generation descriptor is decoded per creative
    Given a decision response with two placements and three creatives, one carrying the contract's descriptor
    When the app decodes the response
    Then that creative has a Lead Generation experience equal to the descriptor
    And the other creatives have none and decode as before

  Scenario: An unknown experience type is unusable but the response still decodes
    Given a creative whose experience type is "quiz"
    When the app decodes the response
    Then that creative's experience is unsupported with type "quiz"
    And its sibling creatives are intact

  Scenario Outline: A malformed descriptor is unusable but the response still decodes
    Given a creative whose Lead Generation descriptor has <defect>
    When the app decodes the response
    Then that creative's experience is unsupported
    And the rest of the response is intact

  Scenario: Unknown prefill keys are dropped
    Given a descriptor listing the prefill keys email, homeAddress, email and 3
    When the app decodes the response
    Then the prefill keys are exactly email

  Scenario: The preparation token never appears in debug output
    Given a creative carrying a Lead Generation experience
    When the app prints, describes or dumps the creative or its experience
    Then the preparation token appears nowhere in the output

  Scenario: A scenario runner on a host without a secure form view can declare what a capable device would
    Given a platform without a secure form view and an opted-in app
    When the runner declares that a secure form view is available
    Then the request declares the keys the app holds
    And when the runner puts the platform default back the request declares nothing
