# Native Gherkin lowering

Use this reference for executable L3 behavior, especially Web plus mobile UI work.

## One source, native execution

```text
FEATURE.md                         intent, rules, links, Green Contract
<feature>.feature                 only executable scenario source
  -> official Gherkin parser      Pickles, stable IDs, platform tags
  -> Web steps                    playwright-bdd -> Playwright -> Web report
  -> typed mobile bindings        Maestro YAML -> Android report
                                               -> iOS report
  -> reconciliation              counts, hashes, failures, cleanup
```

Do not extract executable Gherkin from Markdown. Do not parse scenario lines with ad hoc regular expressions. Do not use CucumberJS as a runner-of-runners.

## Scenario and binding contract

- Require exactly one stable `@BATDD-*` tag per scenario.
- Require explicit `@web` or `@mobile` selection.
- Resolve every selected step to exactly one binding per selected lane.
- Keep Web mechanics in `*.steps.ts` and return typed Maestro commands from `*.bindings.ts`.
- Serialize YAML in one compiler boundary, never in bindings.
- Keep bindings free of Nx invocations and native test entrypoint imports.

## Cross-platform execution

Treat `mobile` as an authored behavior lane and Android/iOS as distinct native executions. Reuse one Maestro flow only when the product behavior, app identity input, and selectors are portable. Otherwise parameterize generated native artifacts without forking the Gherkin semantics.

Use target vocabulary equivalent to:

```text
<surface>:contract
<surface>:e2e-web
<surface>:e2e-mobile-android
<surface>:e2e-mobile-ios
<surface>:e2e-reconcile
<surface>:e2e
```

Nx owns ordering, server lifecycle, device preparation, invocation, and aggregation. Playwright and Maestro own execution.

## Count and hash law

Record separately:

- source scenario count and source SHA-256;
- selected count by authored platform tag;
- generated Playwright test and Maestro flow counts/hashes;
- executed Web, Android, and iOS counts from native reports;
- skips, failures, errors, device identity, duration, and report hash.

Reject zero selection, missing/ambiguous bindings, missing app identity, wrong device, stale generated artifacts, count mismatches, and a shared mobile result falsely reported as two operating-system executions.

## RED and cleanup

A new platform lane may use absent-app capability RED only when the native runner selects the intended scenario, connects to the intended emulator/simulator, and fails precisely at application installation or launch. Installation dialogs and development-client prompts are harness state and stay outside frozen behavior flows.

Stop proof-scoped servers and processes. Preserve pre-existing devices unless the assignment authorizes shutdown. Record installed-app delta and any intentionally retained evidence.
