Feature: The advertiser is told what the viewer did in the form, once
  As an advertiser
  I want to know that a viewer opened or started my form, and that the website link was clicked
  So that reporting is right, without a form or a retry ever being able to count an event twice

  Scenario: An event fires the address the form listed for it
    Given the form was activated with an address for form_open and form_start
    When the form reports form_open
    Then that address is requested once and form_start's is not

  Scenario: An event fires once per form, however often it is reported
    Given form_open already fired
    When the form is hidden, shown and reports form_open again
    Then nothing more is requested

  Scenario: The form can only name an event, never supply an address
    When the form reports an event that was not listed, or one that carries an address
    Then nothing is requested

  Scenario: Preparing, activating and prefill report nothing
    When the form is prepared, activated and prefilled
    Then no address is requested

  Scenario: A failed report is retried twice, then given up
    Given the first two attempts fail
    Then a third attempt is made after 1 second and then 2 seconds
    And when all three fail, one line names the event and never the address

  Scenario: A slow or failing report never holds the form
    When the report takes seconds to answer
    Then the form keeps working while it is retried in the background
