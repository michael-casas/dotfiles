# Architecture Deepening Reference

Use this reference when judging whether source code should be annexed into GOD-LOCK.

This reference adapts the vocabulary and principles from Matt Pocock's `improve-codebase-architecture` skill.

## Vocabulary

Use these terms exactly.

- **Module**: anything with an interface and implementation. It may be a function, class, package, slice, app feature, or tier-spanning concept.
- **Interface**: everything a caller must know to use the module correctly: types, invariants, ordering constraints, error modes, configuration, and performance expectations.
- **Implementation**: the code inside a module.
- **Depth**: leverage at the interface. A deep module provides a lot of behavior behind a small, understandable interface. A shallow module exposes nearly as much complexity as it hides.
- **Seam**: where an interface lives; a place behavior can change without editing in place.
- **Adapter**: a concrete thing satisfying an interface at a seam.
- **Leverage**: what callers gain from a deep module.
- **Locality**: what maintainers gain from a deep module: change, bugs, knowledge, and verification concentrate in one place.

## Principles

### Deletion test

Imagine deleting the module.

- If complexity vanishes, the module was likely pass-through and should not be annexed as-is.
- If complexity reappears across many callers, the module was earning its keep and may be worth annexing or deepening.

### Interface is the test surface

Tests should cross the same interface callers use. If tests must reach past the interface, the module is probably the wrong shape.

### One adapter means hypothetical seam

Do not introduce a seam only because a pattern feels clean. A seam is justified when behavior actually varies. Production adapter plus test adapter may justify a seam. Two production variants strongly justify a seam.

### Depth is not line count

Do not judge module depth by implementation size. Judge by how much capability callers receive per unit of interface they must understand.

## Dependency categories

Classify dependencies before deciding how to annex.

### In-process

Pure computation or in-memory state with no I/O. Usually safe to deepen directly. Test through the new interface.

### Local-substitutable

Dependency has a local test stand-in, such as in-memory filesystem or PGLite for Postgres. Deepen if the stand-in exists. Keep the seam internal unless callers need variation.

### Remote but owned

Dependency crosses a network or service seam but is owned by the system. Define a port at the seam. Production uses HTTP/gRPC/queue adapter. Tests use in-memory adapter.

### True external

Third-party services such as Stripe, Twilio, analytics providers, or external APIs. Inject an external dependency behind a port. Tests use mock adapter.

## Annexation implications

- In-process valuable concepts often become reusable packages.
- Local-substitutable concepts may become packages with test harnesses.
- Remote-but-owned concepts often become domain modules with ports/adapters.
- True external integrations should be wrapped behind GOD-LOCK-owned interfaces.

## Testing strategy

Replace tests, do not layer tests blindly.

- Delete tests for shallow source modules when new interface-level tests cover behavior.
- Preserve tests that encode real business rules.
- Rewrite tests that encode valuable behavior but target the wrong interface.
- Add adapter tests only where adapter behavior matters.
