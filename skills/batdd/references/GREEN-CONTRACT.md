# Green Contract

Define the complete deterministic meaning of GREEN before product implementation.

## Required row fields

Each new or changed contract row records:

- stable row ID and source authority;
- basic or adversarial form;
- lowest faithful L1, L2, or L3 classification;
- selected platform, lowerer, native runtime/device, file, test/scenario identity, and exact Nx target;
- required or profile-backed N/A status;
- expected meaningful RED;
- observable GREEN;
- isolation and cleanup obligation;
- source/selected/generated/executed count expectation and evidence artifact requirement.

Store detailed rows in the feature coverage surface or assignment artifact. Physical `*.feature` remains canonical for scenario text; do not duplicate Gherkin into the Green Contract.

For a full UI profile, represent Web Playwright, Android Maestro, iOS Maestro, and reconciliation as independently visible rows. One generated Maestro flow may satisfy both mobile rows only when each operating system produces a distinct nonzero native result.

## All-RED checkpoint

For new behavior, prove every new or changed row RED before the first product implementation write.

Valid RED:

- selects the intended nonzero tests/scenario;
- runs the intended project, target, layer, and runtime;
- reaches a working harness and fails on missing or incorrect behavior;
- records exact command, working directory, revision, exit code, and decisive output.

Invalid RED:

- syntax or module-resolution failure;
- missing unrelated dependency;
- broken fixture or unavailable required harness;
- wrong target/runtime;
- zero selection, unloaded binding, pending step, or empty assertion;
- intentionally damaging existing behavior to manufacture failure.

Regression work reproduces the defect. A pure refactor normally begins from characterization GREEN rather than fake RED.

## Freeze

Freeze after all required rows have valid RED and before the first product GREEN write:

- scenario identity, title, wording, and semantics;
- native test titles and mappings;
- observable assertions and expected values;
- status codes, envelopes, persistence, no-write, and forbidden guarantees;
- target vocabulary, artifact schema, cleanup, and selected evidence.

Contract correction requires the declared authority and a new evidenced RED boundary.

## Additive proof after freeze

For the canonical directive, new counterexamples to existing requirements may add regression proof after freeze. Preserve all frozen assertions and behavioral meaning, demonstrate the defect before repairing it, and retain the added test. This does not authorize new behavior or acceptance changes; those require the declared amendment authority. The initial all-RED checkpoint still applies to all initially required rows.

## Completion

All required rows GREEN plus affected standing, live-boundary, cleanup, and evidence gates produces `READY_FOR_REVIEW` for the canonical directive, or the explicit `READY-FOR-AUDIT` marker required by a legacy assignment. Independent verification and authorized judgment produce shippability.
