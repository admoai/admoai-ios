Feature: The form runs in a locked-down web view that talks only through the bridge
  As a publisher's tech team and as the viewer
  I want the form page to be the only thing that can reach the SDK, and nothing else to run in the form's web view
  So that a frame, link or popup from elsewhere can never impersonate the form, read what I type or leave the form

  Scenario: A message from the form's own page is delivered
    Given the form page is loaded from the launch origin
    When the page posts a message through AdmoaiBridge
    Then the SDK receives it

  Scenario: A message from a frame inside the page is refused
    When an embedded frame posts a message
    Then the SDK refuses it

  Scenario: A message from another origin is refused
    When a page from another origin posts a message
    Then the SDK refuses it

  Scenario: A message that is not text is refused
    When the page posts something other than a string
    Then the SDK refuses it

  Scenario: Navigation away from the form is cancelled
    Given the surface loaded the form's launch address once
    When the page navigates anywhere: another origin, a non-https address, another path, the launch address again, a reload or a form POST
    Then the navigation is cancelled

  Scenario: Popups never open
    When the page tries to open a window
    Then it gets nothing

  Scenario: Messages from the SDK arrive as text, exactly
    When the SDK sends text with quotes, a closing script tag, newlines and Unicode
    Then the page's onmessage and every message listener receive that exact text as the event data

  Scenario: A page that cannot load, or a lost renderer, is reported
    When the form page cannot be reached, answers with an HTTP error, or the web content process ends
    Then the SDK is told the page failed, and that a 4xx answer will not change on a reload
    And a navigation the surface itself cancelled is not reported as a failure

  Scenario: The web view keeps nothing and is released
    Then it uses non-persistent storage
    And after teardown it is released
