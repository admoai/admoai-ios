Feature: A Lead Generation form is prepared, shown and submitted without surprises
  As an advertiser and as the viewer who taps the ad
  I want the form ready when I tap, shown only when it can be used, and never leaking what I type or what the app knows
  So that opening a form feels instant, a failed one recovers or steps aside, and nothing personal reaches the app's code

  The controller only reports a state and, once submitted, the lead id and when it was accepted. Links and form events the
  page requests are validated and ignored in this item. Contact values are supplied in a later
  item: prefill is sent empty for now.

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

  Scenario: A submission reports only its lead id and when it was accepted
    When the form reports submitted
    Then the state is submitted with the lead id and the time the form accepted it, and nothing else

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
    And a descriptor whose form instance id the contract would refuse gets no controller either

  Scenario: A form the page server refuses ends at once
    Given Lead Generation is off and the form page answers 404 form_not_available
    When the viewer taps the creative
    Then the state is failed with form_not_available, not retryable, and nothing waits for a page that will never speak
    And a launch address that redirects ends the form with navigation_blocked

  Scenario: A reload starts from a clean page
    Given the page's renderer was lost before activation and the app retries
    Then the reloaded page is treated as a new page: a load failure on it ends the form as temporary_failure instead of leaving it preparing

  Scenario: Hiding and showing while submitting tells the form without leaving submitting
    Given the form is submitting
    When the surface is hidden and shown again
    Then the form hears one became_hidden and one became_visible, the state stays submitting, and the submission completes normally

  Scenario: A delegate that hides the surface the moment the form shows does not break the bridge
    Given the app hides the surface from its visible callback
    Then the form hears became_visible before became_hidden and the state is readyToShow, not failed

  Scenario: A renderer lost during a retryable failure is reloaded on retry
    Given the form reported a retryable failure before activation
    When the page's renderer is lost and the app retries
    Then the page is loaded again, instead of sending retry_prepare to a page that is gone

  Scenario: A delegate that opens the form from the prepared callback activates it once
    Given the viewer tapped before the form was prepared
    When the delegate also calls open from the prepared callback
    Then activate is sent once

  Scenario: A failure after activation offers no activation retry
    Given the form is activated
    When the form reports a retryable failure
    Then the state is failed, not retryable

  Scenario: A page that speaks after the deadline is never sent the token
    Given the form is loading and its descriptor expires before the page announces itself
    Then the state is expired and nothing is sent

  Scenario: An activation after the deadline never happens
    Given the viewer tapped while preparing, or the app retries an activation, after the descriptor expired
    Then the state is expired and no activate is sent
