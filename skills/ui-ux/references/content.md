# Content

Concern: the words in the interface. UX copy, microcopy, labels, error text, empty
states, placeholder and marketing copy, tone, and localization. Words appear in an
interface to make it easier to understand and use; they are design material, not
decoration.

Owned elsewhere: how the words are set is `typography.md`; which states need words is
`interaction.md`; naming of destinations is `navigation.md`.

## 1. Principles

- Write from the user's side. Name things by what the user understands, not by how the
  system is built: "notifications", not "webhook config".
- Say what a thing is or does in plain terms. Specific and legible beats clever.
- Active voice, plain verbs, sentence case, no filler. Each element does one job.
- One name per concept and one name per action through the whole flow. The button that
  says "Publish" produces a message that says "Published".
- Say each idea once. If the heading explains the state, the next line adds something
  new or is removed.
- One register per screen. Tone adapts to the moment; voice stays the same.
- Cut until removing another word would lose meaning or a recovery path.

## 2. By element

| Element | Rule |
|---|---|
| Button, link | Verb plus object naming the outcome: "Save changes", "Delete project". Fits on one line. Link text makes sense out of context. |
| Destructive action | Names the object and the consequence. Prefer undo. When confirming, the confirm button repeats the action's verb, not "Yes" or "OK". |
| Field label | Persistent and visible. The placeholder is an example, never the label. |
| Helper text | Answers the question the user has, before submission. Does not restate the label. |
| Validation | Says what needs attention and how to fix it. Does not blame. |
| Error | What failed; why, if known and useful; what to do next. In the interface's voice. No apology, no vagueness, no internal code as the main message. |
| Empty state | What will appear here and the action that starts it. Distinguish first use, no results, filtered out, no permission, and failed to load. |
| Loading | Names the real operation when the wait is meaningful. Shows real progress or none. |
| Success | Confirms the outcome briefly. Mentions a next step only if it changes what the user does. |

- Serious moments (payment, deletion, privacy, access loss, blocked work) get plain,
  serious language. Warmth is fine; jokes are not.
- Do not promise a cause or a fix the system cannot know.

## 3. Marketing and placeholder copy

- Write copy for this product: what it does, for whom, with what proof. Concrete nouns
  and verbs. Filler is AUDIT `CONTENT-02`; the stock vocabulary of generated marketing
  copy is named in `CONTENT-07`.
- Section copy carries one idea. A heading of about eight words and a supporting
  sentence of about twenty-five is a sound starting size, not a quota.
- When the brief supplies no content, draft real sentences from the subject. No lorem
  ipsum. Mark drafts and sample values as such in the handoff, and where a reader could
  mistake them for fact.
- Sample names, companies and numbers should be plausible for the subject and locale,
  and varied: different people get different names and avatars. Never present sample
  figures as real metrics.
- A quotation needs a real source. Without one, leave the slot marked for the user.

## 4. Localization

- Write complete sentences with named variables. Do not build messages by joining
  fragments.
- Use the platform's formatters for dates, numbers, currency and plurals.
- Allow 30 to 40 percent expansion. Do not set fixed widths on text containers.
- Keep accessible names aligned with the visible label.

## 5. Final read

Before handoff, re-read every visible string in context, including alt text, labels and
error messages. Rewrite any that is ungrammatical, has an unclear referent, sounds
ornamental, or says nothing. When unsure, replace it with a plain functional sentence.

## Audit coverage

AUDIT items `CONTENT-01` to `CONTENT-03`, and `CONTENT-04` to `CONTENT-10`.
Related: `SLOP-03` (false structure), `DARK-01` and `DARK-04` (deceptive terms or
urgency), `INTER-02` and `INTER-07` (state and error wording), `A11Y-14` (accessible
names).
