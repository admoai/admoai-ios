Feature: The SDK and the form speak one validated message protocol
  As a publisher's tech team
  I want every message between the SDK and a Lead Generation form checked against the shared contract
  So that a page that misbehaves, or a message that is stale, forged or oversized, can never change what my viewers see or leak what my app holds

  The contract is vendored in Tests/AdMoaiTests/Fixtures/interactive-experience/
  (bridge-messages.json, error-codes.json, bridge/**). The SDK's table of limits is asserted equal
  to it. Messages added by the pack delta after #7127 (bridgeVersion, submitting, submit_failed,
  the submitted order, two constants) are held in the SDK's table and excluded from that equality
  until the pack is re-vendored. A refusal names a message type and a field, never a value.

  Scenario: Every valid message from the form is accepted
    Given the identity in context.json and the messages the contract says must precede it
    When the SDK validates each valid fixture in bridge/runtime-to-app
    Then each is accepted as its typed message

  Scenario: Every invalid message from the form is refused
    When the SDK validates each fixture in bridge/invalid/runtime-to-app
    Then each is refused

  Scenario: What the SDK sends is what the contract shows
    When the SDK encodes each message the fixtures in bridge/app-to-runtime show
    Then the JSON equals the fixture, and the form's own validator accepts it

  Scenario: The SDK cannot send what the contract forbids
    When the SDK is asked to send a prefill value over 256 characters, a key the form did not request, or a gender the form does not offer
    Then it refuses before anything is sent
    And an unknown prefill key or presentation cannot even be written

  Scenario: A message from the app's own direction is refused as incoming
    Given the form sends a message only the app may send
    Then the SDK refuses it

  Scenario: Identity is checked on every message
    Given a message with another channel, or another form instance
    Then the SDK refuses it

  Scenario: Order is enforced
    Given a message whose predecessor has not been exchanged in this instance
    Then the SDK refuses it
    And website links are valid after a submission only, privacy links once the form is shown
    And an event is valid only when the form's activation listed it

  Scenario: Size and shape are bounded
    Given a message over 16384 bytes, text that is not JSON, or an unknown field
    Then the SDK refuses it

  Scenario: A page that speaks another bridge version is refused
    Given a bridge_ready naming a bridge version this SDK does not know
    Then the SDK refuses it, so no initialize is sent

  Scenario: Hostile text round-trips exactly
    Given a prefill value with quotes, a closing script tag, newlines and Unicode
    When the SDK encodes it and the form decodes it
    Then the value is identical

  Scenario: A refusal never contains the token or a value
    Given messages carrying the preparation token or a contact value in a refused position
    Then the refusal, and every description of a message the SDK sends, shows neither

  Scenario: The SDK's table equals the contract
    Then every vendored message, field, limit, enum and pattern equals the SDK's, except those added by the pack delta
