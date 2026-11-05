Feature: Pin views are reported once per decision response
  As a publisher's tech team
  I want trackPointViews to fire each pin's view beacon only the first time it is shown for a given decision response
  So that map re-renders (zoom, pan, cluster expand) do not flood the device and the tracking endpoint with beacons the server will drop anyway

  Reported pin_view counts do not change: the engine already counts a pin view once per
  decision response. This only stops the SDK sending the repeats.

  Scenario: the first render fires every pin's view URLs
    Given a decision response with 50 matched points
    When the app calls trackPointViews with all 50
    Then exactly one GET is sent per view URL in the response

  Scenario: a re-render of the same response fires nothing
    Given trackPointViews has already been called with 50 points from response R
    When the app calls trackPointViews again with the same 50 points from R
    Then no tracking request is sent

  Scenario: a re-render with new pins fires only the new ones
    Given trackPointViews has been called with points A..J from response R
    When the app calls trackPointViews with points F..T from R
    Then view URLs are sent only for K..T

  Scenario: a new decision response starts fresh
    Given pin P was reported for response R1
    When a new decision response R2 also returns pin P with a new view URL
    Then calling trackPointViews for R2 fires P's new view URL

  Scenario: memory is bounded
    Given the app has received 100 decision responses of 50 pins each over a session
    Then the SDK remembers at most 500 fired view URLs, the ten most recent full responses
    And a pin from a forgotten response fires again without an error or a crash

  Scenario: single-point tracking follows the same rule
    Given trackPointView has been called for a point
    When the app calls trackPointView for the same point again
    Then no tracking request is sent

  Scenario: taps and clicks are not deduplicated by this mechanism
    Given a pin whose view was already reported
    When the user taps the pin twice and activates its destination twice
    Then two pin_tap beacons and two click beacons are sent
