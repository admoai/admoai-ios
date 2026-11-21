Feature: The form is told it is visible only while the viewer can see it
  As the viewer of an ad
  I want the form to count as shown only when it is on screen
  So that the form's own open event is true and a hidden form is never reported as shown

  The container tells the controller when it is in a window, not hidden, not transparent, and the
  app is in the foreground (UIKit; iOS only). Its scenarios are covered by the controller's
  hide-and-show scenarios through the same internal calls. Device-level checks (rotation, safe
  areas, background and foreground, modal presentation) happen in the batch QA.

  Scenario: Entering a window shows the form
    When the container enters a window
    Then the controller is told the surface became visible

  Scenario: Hiding or leaving the window hides the form
    When the container is hidden, made transparent, removed from its window, or the app goes to the background
    Then the controller is told the surface became hidden

  Scenario: Full screen respects the safe area
    Given a full screen form
    Then its content stays inside the safe area, and a modal hosts it full screen
