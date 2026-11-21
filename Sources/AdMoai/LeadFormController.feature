Feature: A Lead Generation form is prepared, shown and submitted without surprises
  As an advertiser and as the viewer who taps the ad
  I want the form ready when I tap, shown only when it can be used, and never leaking what I type or what the app knows
  So that opening a form feels instant, a failed one recovers or steps aside, and nothing personal reaches the app's code

  The controller only reports a state and, once submitted, the lead id. Contact values come from
  the app's provider and go to the form once; they are never logged, never passed to the app's
  delegate and not kept (see LeadFormPrefill.feature). Form events fire their listed address once
  (see LeadFormTracking.feature).

  Scenario: The whole happy path
    Given an opted-in app and a prepared form descriptor
    When the app prepares, the viewer taps, and the form is shown
    Then the messages are, in order, initialize, activate, prefill, became_visible
    And the states are preparing, prepared, activating, readyToShow, visible

  Scenario: A tap before the form is ready reuses the same load
    Given the form is still loading
    When the viewer taps
    Then the page is loaded once and initialize is sent once
    And the form is activated as soon as it is prepared

  Scenario: Preparing or opening twice is harmless
    When the app calls prepare and open repeatedly
    Then nothing is loaded or sent twice

  Scenario: Hiding and showing tells the form once per change
    Given the form is visible
    When the surface is hidden and shown again
    Then the form hears one became_hidden and one became_visible and is never activated again

  Scenario: An expired descriptor never loads
    Given the descriptor has expired
    When the app prepares or opens
    Then the state is expired, nothing is loaded, and the token is never sent

  Scenario: A retryable failure can be retried
    Given the form reports a retryable failure while preparing
    When the app retries
    Then retry_prepare is sent and the state is preparing

  Scenario: A retryable failure while activating is retried by activating again
    Given the form reports a retryable failure after the viewer tapped
    When the app retries
    Then activate is sent again, not retry_prepare

  Scenario: A fatal expiry ends the form
    Given the form reports it expired
    Then the state is expired

  Scenario: A page that speaks another bridge version is unavailable
    Given the page names a bridge version the SDK does not know
    Then no initialize is sent and the state is failed, not retryable

  Scenario: A reloaded page is initialised again before activation
    Given the page announces itself twice before the form is activated
    Then initialize is sent twice and the form still reaches readyToShow

  Scenario: A reload after activation fails without a retry
    Given the form is activated
    When the page announces itself again
    Then the state is failed, not retryable

  Scenario: A failed submission returns to visible
    Given the form is submitting
    When the form reports the submission failed
    Then the state is visible and the form retries itself
    And an answer that does not follow a new submitting is refused

  Scenario: A submission reports only its lead id
    When the form reports submitted
    Then the state is submitted with the lead id and nothing else

  Scenario: Disposing is final
    When the app disposes twice
    Then dispose is sent once and the surface is released
    And later messages are ignored and the delegate hears nothing more

  Scenario: The form can ask to be closed
    When the form requests close
    Then the delegate is asked to close

  Scenario: Both presentations reach the form
    Then initialize carries inline or full_screen as the app chose

  Scenario: A refused message changes nothing
    When the form sends a message the contract refuses
    Then the state is unchanged and one warning with the reason only is logged

  Scenario: Nothing the app hears holds the token or a value
    Then no state the delegate receives, printed in any way, contains the preparation token

  Scenario: A tap after the deadline never activates
    Given the form was prepared and its descriptor has since expired
    When the viewer taps
    Then the state is expired and no activate is sent

  Scenario: The failure's code decides whether a retry can help
    When the form reports expired, revoked, form_not_available or unauthorized while preparing
    Then the state is expired for expired and failed, not retryable, for the others
    And rate_limited and temporary_failure are retryable only when the form says so

  Scenario: A page that cannot load is reloaded on retry
    Given the device is offline when the form is prepared, or the page's renderer is lost before activation
    Then the state is failed, retryable
    And retrying loads the page again, instead of sending retry_prepare to a page that is not listening

  Scenario: Losing the renderer after activation is final
    Given the form is activated
    When the page's renderer is lost
    Then the state is failed, not retryable, because what the viewer typed is gone

  Scenario: An app that did not opt in gets no controller
    When the app asks for a controller without having opted in
    Then it gets none

  Scenario: The form receives the values the app holds for the keys it requested
    Given the app holds email and phone and the form requests email and gender
    When the form is activated
    Then prefill carries the email, trimmed, and the gender when it is one of the form's options
    And phone, which the form did not request, is never sent

  Scenario: Blank, over-long and invalid-gender values are not sent
    Given the app answers with a blank name, a 257-character name and a gender the form does not offer
    Then prefill carries none of them

  Scenario: A value that arrives after the deadline is never sent
    Given the app answers for one key after 1.5 seconds
    Then prefill carries the other values and the late one is never sent

  Scenario: With nothing to ask, prefill is sent at once and empty
    Given the form requests keys the app does not hold
    Then prefill is sent immediately with no values

  Scenario: A user change during a lookup ends the form and drops the value
    Given the app is still answering for user A
    When the app switches to user B
    Then the form is disposed and user A's value is never sent to any form

  Scenario: Changing the provider, disabling, or switching or clearing the user disposes every form
    When the app enables interactive experiences with another provider, disables them, or changes or clears the user id
    Then every live form is disposed
    And enabling again with the same provider, or changing only the timezone, disposes nothing

  Scenario: The form can ask the app to open its links outside the form
    When the form requests its privacy policy, and, after the submission, the advertiser's website
    Then the app is asked to open each https address with its purpose
    And the website is refused before the submission and an http address is always refused
    And an app that does not handle links simply does not open them

  Scenario: Form events reach the advertiser once
    When the form reports form_open and form_start, form_open again after being hidden and shown, and an event it did not list
    Then each listed event's address is requested once and nothing else is

  Scenario: At most two forms prepare in the background without being opened
    Given two forms are preparing and never opened
    When a third and a fourth are prepared
    Then they stay idle and wait
    And each starts, in order, when a prepared form is opened, disposed, fails or is released

  Scenario: Opening a waiting form always proceeds
    Given a form is waiting for a slot
    When the viewer taps it
    Then it prepares and activates, leaves the queue, and the forms behind it keep waiting

  Scenario: A waiting form whose descriptor expired never loads
    Given a form waited for a slot past its expiry
    When a slot frees
    Then its state is expired and nothing is loaded

  Scenario: Releasing a controller tears its page down
    When the app releases a controller without disposing it
    Then its page is torn down and its slot is freed

  Scenario: The back press goes to the form only while it is on screen
    Given the form is shown to the viewer
    When the app hands it the viewer's back press
    Then the form consumes it and goes back one stage, or asks to close on its first stage and on its confirmation
    And while submitting the press is consumed and nothing is sent
    And while the form is hidden, not yet shown, failed or disposed the press belongs to the app
