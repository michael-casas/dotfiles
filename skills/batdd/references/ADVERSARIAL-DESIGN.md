# Adversarial Design

Design coverage in two passes before implementation.

## Pass A — basic contract

Identify:

- primary successful outcome;
- ordinary rejection or degradation;
- state created, changed, preserved, or forbidden;
- public actor and observable response;
- explicit scope boundary.

## Pass B — disproof

Assume the obvious implementation passes. Find the smallest counterexamples that make it incorrect, unsafe, unrecoverable, unauthorized, misleading, or operationally unshippable.

Consider when applicable:

- zero, empty, minimum, maximum, malformed, and partially valid values;
- duplicate delivery, replay, idempotency, concurrency, and racing transitions;
- wrong identity, wrong role, insufficient privilege, and destructive action;
- partial write, rollback, and no-write-after-rejection;
- timeout, cancellation, process death, restart, and reconciliation;
- lost or duplicate notification, hook, message, or transport observation;
- stale state, stale cache, and advisory state contradicting durable truth;
- resource leak and cleanup failure on setup, action, assertion, timeout, or cancellation;
- provider interruption versus semantic failure;
- zero-test, wrong-target, assertion-free, or status-only false green;
- browser hydration, visibility, interaction, or device behavior contradicted by a data proxy.

## Assign the lowest faithful layer

- Put exhaustive transformations, boundaries, and local state logic in L1.
- Put real persistence, process, protocol, browser, device, delivery, restart, and cleanup proof in L2.
- Put only representative behaviors capable of invalidating the product promise in L3.

Do not turn the entire adversarial catalog into Gherkin. Native runners own exhaustive seam-local proof.

Every retained adversarial row must trace to a real risk or invariant. Remove duplicate rows that prove the same failure through the same observation.
