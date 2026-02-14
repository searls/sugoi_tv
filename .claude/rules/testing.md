# Testing Rules

Every feature and bug fix must be thoroughly covered by automated tests
that verify correctness without human intervention.

Your work will be evaluated at each review checkpoint (before tool use,
after each turn, and before each commit) against this standard:

- New behavior requires new tests that would fail if the code were reverted
- Bug fixes require regression tests that reproduce the original failure
- "Hard to test" is not a valid exemption — if it runs, it can be tested

# ALLOWED EXCEPTIONS

* IMPORTANT: BECAUSE THIS PROJECT IS SwiftUI, and SwiftUI is a declarative, stateless DSL, there are many cases where code is safely expressed (booleans, very basic control flow) without tests. Writing a standalone test would require an INCREASE in complexity in order to extract something testable, put the function under test, and then invoke it from SwiftUI. In general THIS IS NOT WORTH IT and it's better to leave the SwiftUI code as self-documenting and verified in either UI tests or via manual verification
