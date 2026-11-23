Feature: A form opens with the contact values the app already holds
  As the viewer who opened a lead form
  I want my name or email filled in when my app knows it
  So that I type less, while nothing I did not open is ever read or sent

  Scenario: The app's values reach the form once, within the deadline
    Given the form asks for email and phone and the app holds both
    When the form is activated
    Then the app is asked for both at once and the form receives what arrived within 1.5 seconds

  Scenario: Only values the form may receive are sent
    Given the app answers with a blank value, a value of 257 characters, and a gender that is not an option
    Then none of them is sent, and a value of exactly 256 characters is
    And surrounding whitespace is trimmed

  Scenario: A late value is discarded
    Given the app answers for phone after the deadline
    Then the form received the other values at the deadline and phone is never sent

  Scenario: Waiting stops as soon as every key answered
    Given the app answers every key at once
    Then the form is not kept waiting for the deadline

  Scenario: An app that never answers cannot hold the form
    Given the app never answers for one key
    Then the form receives the other values at the deadline

  Scenario: Nothing is asked when there is nothing to ask
    Given the form requests keys the app does not hold
    Then the form receives no values and the app is not asked

  Scenario: A value that arrives after the deadline is dropped even before the wait ended
    Given the deadline passed but the wait has not been ended yet
    When the app answers for phone
    Then phone is never sent and the form receives what arrived before the deadline
