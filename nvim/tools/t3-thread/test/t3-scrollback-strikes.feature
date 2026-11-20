@terminal
Feature: Theme-correct T3 terminal history without destructive redraws
  Background:
    Given the active theme has a popover background distinct from the editor background
    And only synthetic conversation fixtures or explicitly owned throwaway threads are used

  @BATDD-T3STRIKE-01
  Scenario: Open a marked AGENT slot and read themed scrollback
    Given an owned thread with finished text, code, and separator history is marked in slot 9
    When I open AGENT with <leader>a and open slot 9
    And I enter COMMAND and scroll above the live region
    Then ordinary text canvas, separator, erased, and margin cells have the popover background
    And intentional code and user-bubble backgrounds retain their theme tokens
    And each committed item is present exactly once in order
    And no other thread is opened or changed

  @BATDD-T3STRIKE-02
  Scenario: Open the same history by the existing direct route
    Given the direct <leader>hi target is an explicitly owned throwaway thread
    When I open that thread by <leader>hi
    And I enter COMMAND and scroll above the live region
    Then ordinary text canvas, separator, erased, and margin cells have the popover background
    And intentional code and user-bubble backgrounds retain their theme tokens
    And each committed item is present exactly once in order
    And no other thread is opened or changed

  @BATDD-T3STRIKE-03
  Scenario: Preserve history across resize, reopen, and thread switching
    Given two owned thread clients have distinct committed history markers under one unchanged theme
    When I resize the terminal from 100 by 30 cells to 80 by 24 cells and back
    And I hide the popover with COMMAND :q and reopen the first client
    And I switch to the other client and back
    Then each client's committed content remains complete, ordered, and unduplicated
    And ordinary historical cells keep their committed theme background
    And intentional surfaces remain intact
    And thread switching keeps the same popover window identity
    And hide and reopen reuse the first client's buffer and running process

  @BATDD-T3STRIKE-04
  Scenario: Shrink terminal height during an existing long stream without clearing history
    Given an 80 by 24 terminal already has committed history and a capped 20-row live stream
    When its height becomes 12 rows while that stream continues
    Then the output never clears the whole screen or scrollback
    And no previously committed history marker is emitted again
    And the live region fits below the new terminal height
    And no client or popover window is recreated to repaint

  @BATDD-T3STRIKE-05
  Scenario: Bound redraws while idle and streaming at stable size
    Given an 80 by 24 terminal has committed history and no pending action
    When the UI settles and receives an unchanged idle rerender
    Then no terminal repaint bytes are emitted for the unchanged live frame
    When five distinct live updates are delivered 80 milliseconds apart without a new history item
    Then no full-screen clear or Static history replay occurs
    And each changed live frame causes at most one erase-and-redraw batch
    And no terminal repaint is triggered by an idle repeating timer

  @BATDD-T3STRIKE-06
  Scenario: Keep COMMAND, INSERT, dismiss, and hide semantics
    Given a T3 popover has a draft and an open dismissible menu
    When I press Esc in INSERT
    Then the menu closes and the popover enters COMMAND without sending raw Esc or interrupting the run
    When I press Esc again
    Then it stays in COMMAND and remains visible
    When I press Ctrl+] in COMMAND and type q
    Then it enters INSERT and q is draft text rather than a hide action
    When I press Ctrl+] again and type :q in COMMAND
    Then only the popover is hidden and the client and draft remain available on reopen

  @BATDD-T3STRIKE-07
  Scenario: Keep ordinary terminals independent from the T3 popover theme
    Given an ordinary hcmux terminal and a T3 client share the same editor session
    When the T3 client is opened, resized, switched, and hidden
    Then the ordinary terminal's configured display and OSC colour answers are unchanged
    And global Normal and Cursor highlights are unchanged
    And no unrelated client process is stopped or recreated
