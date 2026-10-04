# Intent to Jira tickets

## Classification and ownership

- An Epic is a Feature Charter: a technical PRD for a coherent capability, covering problem, users, functional and non-functional requirements, measurable acceptance, boundaries and open decisions. Do not create an Epic for each implementation step.
- A Bug is a violation of expected supported behavior. Its description is a completed canonical Directive with Class: fix. A standalone Bug does not need an artificial Epic. Link it to an existing feature Epic when that relationship is real and the project supports it.
- A child Task is the canonical Directive and maps its obligations to Epic requirements and acceptance IDs. Use Class: feat, refactor, docs, test, or another appropriate Conventional Commit type; Jira issue type and commit class are separate fields.
- A Jira Subtask is an evidence-based fulfilment requirement of its parent Directive: name one obligation, its Directive reference and the evidence that closes it. Assignment or tracking alone does not define a Subtask. Local checklist steps organize execution and map to those obligations; they are not Jira issues without actual keys. Do not create ticket noise for every test command or RED/GREEN phase.
- Maintenance that is neither a feature nor a defect may be a standalone Task; explain classification rather than inventing a feature or Bug.

Identify the owning repository and accountable owner. For Atlantis, ops-platform owns current Ops compatibility; the Nx monorepo owns its accepted shared domains/infrastructure. Cross-repository work names separate ownership and interface obligations. Do not infer completed annexation.

## Intake

Read relevant repository instructions and existing evidence. Extract actor, trigger, current behavior, requested outcome, impact, affected surfaces, exclusions, dependencies and acceptance. Separate observations from assumptions and implementation suggestions. Ask only questions that materially change behavior, ownership or scope; continue grounded drafting where possible.

Search existing issues before creating new ones when connected Jira access exists. Read relevant Epic/children and decisions completely, including pagination. Avoid duplicate features or bugs. Record source links, retrieval time and issue update times. Do not invent ticket IDs, assignees, statuses, priorities, affected versions, reproduction results or acceptance decisions. Redact secrets and private data.

A report with unverified reproduction is still a valid Bug draft: label it reported/unreproduced and make reproduction the first proof obligation. Never present a suspected root cause as established fact.

## Feature Epic

Prepare the Epic batch first; publish only within the recorded grant. Before writing Tasks for an Epic, deeply inspect its Feature Charter, current implementation, dependencies, failure risks and unresolved decisions. Record the findings and requirement/acceptance coverage that justify its breakdown. Do not bulk-generate Tasks from Epic titles.

Fill templates/EPIC.md: problem/outcome/users, functional and non-functional requirements, ownership, scope/exclusions, stable acceptance IDs and forbidden effects, integration gates, delivery/review boundary and decisions. The initial Epic may state that child breakdown is pending introspection; fill child inventory/dependencies only after that review. Every child contributes an observable deliverable or necessary enabling outcome. Dependencies reflect actual prerequisites, not arbitrary serial numbering. Keep testing within each behavioral task rather than making a separate testing ticket hide unfinished implementation.

Draft each child description in templates/DIRECTIVE.md syntax. Cover objective, problem, authority, bounded behavioral contract, proof, Definition of Done and review handoff. Map each Epic acceptance ID to children and aggregate proof. Use temporary local proposal IDs before Jira creation; replace them with actual returned keys and verify parent links afterward. Derive each Subtask from one Directive obligation and specify its closing evidence; a checked obligation does not independently accept its parent Task.

For an owner-designated long-lived Epic, version the approved delivery slice and its acceptance/child inventory. New features amend the Feature Charter and receive fresh introspection; completing a slice does not close the long-lived Epic.

## Bug Directive

Use templates/DIRECTIVE.md as the complete description, not just a link to a template. Fill all fields; Class is fix and completion gate remains READY_FOR_REVIEW. Add the following concrete detail inside Problem Statement/Context and Supporting Proof without removing the canonical sections:

- Environment and affected version/build when known.
- Minimal numbered reproduction steps and necessary preconditions.
- Actual result versus expected supported result, with expectation source.
- Reproduction state: observed, reported/unreproduced, intermittent, or no longer reproducible; frequency when known.
- User/business impact and Severity. Severity describes impact; Jira priority is a separate project field and must use discovered valid values.
- Redacted evidence/log/screenshot links, first/last observed time when known, and any workaround.
- Suspected cause explicitly labeled as a hypothesis, or unknown.
- Regression contract: fail on the defect through a faithful harness, pass on the repair, preserve adjacent supported behavior and forbidden effects.

Do not prescribe a speculative fix as acceptance. Retain meaningful RED, frozen behavior, applicable layers, self-review, cleanup and independent review. Production access or reproduction against live data requires its own authority.

## Draft versus executable issuance

A ticket may be publishable before a worker/worktree/branch exists. State operational bindings as unassigned and execution status as NOT ISSUED, with the specific dispatch prerequisites; never invent a branch, PR or grant. Product ambiguities remain explicit open decisions. Such a ticket is not executable until those decisions and bindings are resolved.

For an execution-ready Directive, replace every template placeholder and GHERKIN_REQUIRED sentinel with concrete source-backed behavior (or justified nonbehavioral proof), stable scenario IDs, protected boundaries, resolved proof commands/profile and delivery authority. The installed BATDD generator may render the template, but its output still requires the authoring step. Do not send unresolved scaffold output to an implementer.

Version material ticket/Directive amendments. At execution handoff, capture the approved source snapshot and immutable Directive identity. Inline issued behavior is provenance; the selected physical feature is the sole executable scenario source. Ticket authoring never changes frozen acceptance in an active run without its amendment authority.

## Publishing to Jira

A request to create/update specific Jira tickets authorizes that bounded publication. A request to draft tickets or create this skill does not. Respect existing authority without asking again. Discover project, issue types, parent field, required fields, allowed statuses and rich-text format from the available connector/API; do not assume English workflow names or field IDs.

Preserve Directive headings, lists, checklist items, tables and fenced Gherkin when translating Markdown to Jira's supported format. Do not upload raw Markdown as ADF or silently flatten away the contract. Read the created/updated description back and verify semantics, actual key/type, parent/dependencies and acceptance coverage.

Publish the authorized Epic batch first. After each Epic's introspection, publish its canonical Task Directive drafts and evidence-based Subtasks only within the grant, then update its inventory with returned keys. This is not an atomic transaction: record each successful issue and any partial failure. Reconcile uncertain responses before retrying to avoid duplicates; do not delete successful tickets as rollback without authority. For edits, reread current state and preserve unrelated changes; reconcile concurrent scope edits.

Publication ends at TICKETS_PREPARED or TICKETS_PUBLISHED with exact artifact paths or issue links, issue hierarchy, remaining decisions and execution eligibility. It does not start an implementation agent or transition issues to Done. Hand approved tickets and the Directive bindings to Han Solo for the durable execution plan, task commits and final PR-review handoff.

## Authoring check

Confirm type fits intent; owner/repository is explicit; Feature Charters include functional and non-functional requirements; Epic introspection precedes Task breakdown; each Subtask names one Directive obligation and closing evidence; children cover all acceptance in the approved delivery scope (or breakdown is explicitly pending); Bug repro and expectation are honest; descriptions use the canonical structures; unknowns are explicit; no placeholders reach execution; parent/dependency links and published rendering are verified; no ungranted delivery/production/Jira authority is implied.
