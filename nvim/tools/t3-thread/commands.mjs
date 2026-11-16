// Composer `/command` and `$skill` completion. Pure: no I/O, no clock.
//
// Mirrors the T3 desktop composer (t3code apps/web/src/composer-logic.ts,
// components/chat/useComposerMenuItems.ts, composerSlashCommandSearch.ts,
// providerSkillSearch.ts, packages/shared/src/searchRanking.ts). Choosing an item
// only inserts text (`/name ` or `$name `); the T3 server does the rest when the
// message is sent: `/compact` compacts the thread, `$skill` and provider
// commands are expanded for the provider.

const isSpace = (c) => c === " " || c === "\n" || c === "\t" || c === "\r";
// "$5", "$10k", "$2e3" are amounts, not skills (T3's SKILL_TOKEN_REGEX lookahead).
const AMOUNT = /^[0-9][0-9_.,]*(?:[kKmMbBtT]|[eE][0-9]+)?$/;

/** The `/` or `$` token ending at the cursor, or null. */
export function detectTrigger(value, cursor = value.length) {
  cursor = Math.max(0, Math.min(value.length, cursor));
  let start = cursor;
  while (start > 0 && !isSpace(value[start - 1])) start--;
  const token = value.slice(start, cursor);
  if (token.startsWith("/")) {
    // A path such as /usr/bin is not a command.
    if (token.indexOf("/", 1) !== -1) return null;
    return { kind: "slash", query: token.slice(1), start, end: cursor };
  }
  const skill = /^\p{Sc}/u.exec(token);
  if (skill) {
    const query = token.slice(skill[0].length);
    if (AMOUNT.test(query)) return null;
    return { kind: "skill", query, start, end: cursor };
  }
  return null;
}

/** The commands and skills for this thread's provider, preferring its folder's snapshot. */
export function catalog(providers, instanceId, cwd) {
  if (!providers || !instanceId) return null;
  const provider = providers.find((p) => p.instanceId === instanceId);
  if (!provider) return null;
  const snap = cwd && provider.workspaceSnapshots?.find((s) => s.cwd === cwd);
  return {
    instanceId,
    cwd: cwd || null,
    hasSnapshot: Boolean(snap && !snap.slashCommandsPending),
    slashCommands: snap?.slashCommands ?? provider.slashCommands ?? [],
    skills: snap?.skills ?? provider.skills ?? [],
  };
}

/** Keep the folder snapshots a refresh returned; a reply may carry only the asked-for one. */
export function mergeProviders(previous, next) {
  if (!previous) return next;
  return next.map((p) => {
    const old = previous.find((o) => o.instanceId === p.instanceId);
    const snaps = new Map(
      (old?.workspaceSnapshots || []).map((s) => [s.cwd, s]),
    );
    for (const s of p.workspaceSnapshots || []) snaps.set(s.cwd, s);
    return {
      ...p,
      slashCommands: p.slashCommands ?? old?.slashCommands ?? [],
      skills: p.skills ?? old?.skills ?? [],
      workspaceSnapshots: [...snaps.values()],
    };
  });
}

// ── ranking (port of @t3tools/shared/searchRanking) ──────────────────────────
function boundaryIndex(value, query, markers) {
  let best = null;
  for (const m of markers) {
    const i = value.indexOf(m + query);
    if (i !== -1 && (best === null || i + m.length < best)) best = i + m.length;
  }
  return best;
}
function subsequence(value, query) {
  let q = 0,
    first = -1,
    prev = -1,
    gaps = 0;
  for (let i = 0; i < value.length; i++) {
    if (value[i] !== query[q]) continue;
    if (first === -1) first = i;
    if (prev !== -1) gaps += i - prev - 1;
    prev = i;
    if (++q === query.length)
      return (
        first * 2 +
        gaps * 3 +
        (i - first + 1 - query.length) +
        Math.min(64, value.length - query.length)
      );
  }
  return null;
}
export function scoreMatch(value, query, base) {
  if (!value || !query) return null;
  const penalty = Math.min(64, Math.max(0, value.length - query.length));
  if (value === query) return base.exact;
  if (base.prefix !== undefined && value.startsWith(query))
    return base.prefix + penalty;
  if (base.boundary !== undefined) {
    const i = boundaryIndex(
      value,
      query,
      base.markers ?? [" ", "-", "_", "/"],
    );
    if (i !== null) return base.boundary + i * 2 + penalty;
  }
  if (base.includes !== undefined) {
    const i = value.indexOf(query);
    if (i !== -1) return base.includes + i * 2 + penalty;
  }
  if (base.fuzzy !== undefined) {
    const s = subsequence(value, query);
    if (s !== null) return base.fuzzy + s;
  }
  return null;
}
const best = (scores) => {
  const ok = scores.filter((s) => s !== null);
  return ok.length ? Math.min(...ok) : null;
};
const NAME = {
  exact: 0,
  prefix: 2,
  boundary: 4,
  includes: 6,
  fuzzy: 100,
  markers: ["-", "_", "/", ":"],
};
function scoreCommand(command, query) {
  return best([
    scoreMatch(command.name.toLowerCase(), query, NAME),
    scoreMatch(describeCommand(command).toLowerCase(), query, {
      exact: 20,
      prefix: 22,
      boundary: 24,
      includes: 26,
    }),
  ]);
}
function scoreSkill(skill, query) {
  return best([
    scoreMatch(skill.name.toLowerCase(), query, NAME),
    scoreMatch((skill.displayName || skill.name).toLowerCase(), query, {
      exact: 1,
      prefix: 3,
      boundary: 5,
      includes: 7,
      fuzzy: 110,
    }),
    scoreMatch((skill.shortDescription || "").toLowerCase(), query, {
      exact: 20,
      prefix: 22,
      boundary: 24,
      includes: 26,
    }),
    scoreMatch((skill.description || "").toLowerCase(), query, {
      exact: 30,
      prefix: 32,
      boundary: 34,
      includes: 36,
    }),
    scoreMatch((skill.scope || "").toLowerCase(), query, {
      exact: 40,
      prefix: 42,
      includes: 44,
    }),
  ]);
}
function rank(list, query, score, tie) {
  if (!query) return list;
  return list
    .map((item) => ({ item, score: score(item, query) }))
    .filter((r) => r.score !== null)
    .sort((a, b) => a.score - b.score || tie(a.item).localeCompare(tie(b.item)))
    .map((r) => r.item);
}

const describeCommand = (c) =>
  c.description || c.input?.hint || "Run provider command";
const describeSkill = (s) =>
  s.shortDescription ||
  s.description ||
  (s.scope ? `${s.scope} skill` : "Run provider skill");
function dedupe(list) {
  const seen = new Set();
  return list.filter((x) => {
    const k = x.name.trim().toLowerCase();
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/**
 * Menu for the composer, or null when no menu belongs at the cursor.
 * `{ trigger, items: [{id,label,description,insert}], empty }`
 */
export function menu(value, cursor, cat, { working = false } = {}) {
  const trigger = detectTrigger(value, cursor);
  if (!trigger) return null;
  const query = trigger.query.trim().toLowerCase();
  const base = { trigger, items: [], empty: "" };
  if (trigger.kind === "slash") {
    // Provider commands only work at the start of a message.
    if (value.slice(0, trigger.start).trim() !== "") return null;
    // Like the desktop: /compact only as the whole message, when idle; the
    // provider's /clear would reset a session T3 still treats as live.
    const alone = value.slice(trigger.end).trim() === "";
    const commands = dedupe([
      ...(cat?.slashCommands || []).filter((c) => c.name !== "model"),
      ...(alone ? [{ name: "model", description: "Choose harness, model and effort", action: "model" }] : []),
    ]).filter(
      (c) => c.name !== "clear" && (c.name !== "compact" || (alone && !working)),
    );
    const items = rank(commands, query, scoreCommand, (c) => c.name).map(
      (c) => ({
        id: `slash:${c.name}`,
        label: `/${c.name}`,
        description: describeCommand(c),
        hint: c.input?.hint,
        ...(c.action ? { action: c.action } : { insert: `/${c.name} ` }),
      }),
    );
    return {
      ...base,
      items,
      empty: !cat ? "Loading commands…" : commands.length
        ? "No matching command."
        : "This provider has no commands.",
    };
  }
  if (!cat) return { ...base, empty: "Loading commands…" };
  const skills = dedupe(
    cat.skills.filter((s) => s.enabled !== false && s.userInvocable !== false),
  );
  const items = rank(skills, query, scoreSkill, (s) =>
    (s.displayName || s.name).toLowerCase(),
  ).map((s) => ({
    id: `skill:${s.name}`,
    label: `$${s.displayName || s.name}`,
    description: describeSkill(s),
    insert: `$${s.name} `,
  }));
  return {
    ...base,
    items,
    empty: skills.length
      ? "No skills found. Try / to browse provider commands."
      : "This provider has no skills.",
  };
}

/** Replace the trigger token with the item's text (absorbing a following space). */
export function accept(value, trigger, item) {
  let end = trigger.end;
  if (item.insert.endsWith(" ") && value[end] === " ") end++;
  return {
    value: value.slice(0, trigger.start) + item.insert + value.slice(end),
    cursor: trigger.start + item.insert.length,
  };
}

/** Enter on a fully typed, highlighted command sends it instead of inserting it again. */
export function isComplete(value, trigger, item) {
  return (
    value.slice(trigger.start, trigger.end) === item.insert.trimEnd() &&
    value.slice(trigger.end).trim() === ""
  );
}
