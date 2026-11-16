// Pure /model draft and keyboard transitions. Only the adapter applies a draft.
// Wire/catalog and handoff rules mirror T3's modelTraits.ts, providerInstances.ts
// and state/threadWorkflows.ts. IDs are routing values; labels are display only.
const EFFORT_IDS = new Set([
  "effort",
  "thinking",
  "variant",
  "reasoningEffort",
]);
const values = (map) => [...(map?.values() || [])];
const active = (run) =>
  ["preparing", "queued", "starting", "running", "waiting"].includes(
    run.status,
  );

function supportsHandoff(state) {
  const runs = values(state?.runs);
  const run = runs.filter(active).sort((a, b) => b.ordinal - a.ordinal)[0];
  const threads = values(state?.providerThreads);
  const providerThread =
    threads.find(
      (t) =>
        t.id ===
        (run?.providerThreadId ?? state?.thread?.activeProviderThreadId),
    ) ??
    threads.find(
      (t) => t.appThreadId === state?.thread?.id && t.providerSessionId != null,
    );
  const sessions = values(state?.providerSessions);
  const session =
    providerThread?.providerSessionId != null
      ? sessions.find((s) => s.id === providerThread.providerSessionId)
      : sessions.findLast(
          (s) => s.status !== "stopped" && s.status !== "error",
        );
  if (session)
    return (
      session.capabilities?.sessions?.supportsProviderSwitchingViaHandoff ===
      true
    );
  if (run) return false;
  if (state?.thread?.historyOrigin === "v1_import" || !runs.length) return true;
  return threads.some(
    (t) =>
      t.id === state?.thread?.activeProviderThreadId &&
      t.appThreadId === state?.thread?.id &&
      t.providerInstanceId === state?.thread?.modelSelection?.instanceId,
  );
}

export function harnesses(providers, state) {
  const current =
    state?.thread?.modelSelection?.instanceId ??
    state?.thread?.providerInstanceId;
  const started = Boolean(
    state?.runs?.size || state?.turnItems?.size || state?.providerThreads?.size,
  );
  const locked = started && !supportsHandoff(state);
  return (providers || [])
    .filter((p) => p.enabled && p.status !== "disabled")
    .map((p) => ({
      id: p.instanceId,
      label: p.displayName || p.instanceId,
      provider: p,
      reason:
        locked && p.instanceId !== current
          ? "Start a new chat to switch harnesses."
          : p.availability === "unavailable" || p.status !== "ready"
            ? p.unavailableReason ||
              p.message ||
              `Harness ${p.status || "unavailable"}`
            : null,
    }));
}

// Desktop getDisplayModelName strips a redundant sub-provider qualifier.
export function modelName(model) {
  const name = model.name || model.slug;
  const qualifier = model.subProvider?.trim();
  if (!qualifier) return name;
  const escaped = qualifier.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return (
    name
      .replace(new RegExp(`^${escaped}(?:\\s*[.:/-]\\s*|\\s+)`, "iu"), "")
      .trim() || name
  );
}
function models(provider, state) {
  const list = (provider?.models || []).map((m) => ({
    id: m.slug,
    label: modelName(m),
    model: m,
  }));
  const current = state?.thread?.modelSelection;
  if (
    current?.instanceId === provider?.instanceId &&
    current.model &&
    !list.some((m) => m.id === current.model)
  )
    list.unshift({
      id: current.model,
      label: current.model,
      reason: "Model no longer in catalog",
    });
  return list;
}
function effort(model) {
  const descriptor = model?.capabilities?.optionDescriptors?.find(
    (d) => EFFORT_IDS.has(d.id) || d.role === "reasoning",
  );
  if (!descriptor) return { descriptor: null, items: [] };
  const items =
    descriptor.type === "boolean"
      ? [
          { id: true, label: "On" },
          { id: false, label: "Off" },
        ]
      : (descriptor.options || []).filter(
          (o) => !descriptor.promptInjectedValues?.includes(o.id),
        );
  return { descriptor, items };
}
function defaultEffort(control) {
  if (control.descriptor?.type === "boolean")
    return control.descriptor.currentValue === true;
  return (
    control.items.find((i) => i.id === control.descriptor?.currentValue)?.id ??
    control.items.find((i) => i.isDefault)?.id ??
    control.items[0]?.id ??
    null
  );
}
function seed(provider, model, state) {
  const control = effort(model?.model);
  const current = state?.thread?.modelSelection;
  const same =
    current?.instanceId === provider?.id && current?.model === model?.id;
  const saved = same
    ? current?.options?.find((o) => o.id === control.descriptor?.id)?.value
    : undefined;
  return {
    instanceId: provider?.id ?? null,
    model: model?.id ?? null,
    effort: control.items.some((i) => i.id === saved)
      ? saved
      : defaultEffort(control),
  };
}
export function open(providers, state) {
  const list = harnesses(providers, state);
  const provider =
    list.find((p) => p.id === state?.thread?.modelSelection?.instanceId) ??
    list.find((p) => !p.reason);
  const choices = models(provider?.provider, state);
  const model =
    choices.find((m) => m.id === state?.thread?.modelSelection?.model) ??
    choices.find((m) => m.model?.isDefault) ??
    choices[0];
  return { ...seed(provider, model, state), column: 0, g: false };
}
export function columns(picker, providers, state) {
  const list = harnesses(providers, state);
  const provider = list.find((p) => p.id === picker.instanceId);
  const choices = models(provider?.provider, state);
  const model = choices.find((m) => m.id === picker.model);
  const control = effort(model?.model);
  const raw = [
    { label: "Harness", items: list, value: picker.instanceId },
    { label: "Model", items: choices, value: picker.model },
    { label: "Effort", items: control.items, value: picker.effort },
  ];
  const result = raw.map((c, index) => ({
    ...c,
    focused: index === picker.column,
    selected: c.items.findIndex((i) => i.id === c.value),
    items: c.items.length
      ? c.items
      : [
          {
            id: null,
            label: index === 2 ? "No effort levels" : "No choices",
            reason: "No choices",
          },
        ],
  }));
  result.note =
    provider?.reason ||
    model?.reason ||
    (list.some((p) => p.reason === "Start a new chat to switch harnesses.")
      ? "Start a new chat to switch harnesses."
      : "") ||
    (providers == null
      ? "Loading harnesses…"
      : !list.length
        ? "No enabled harnesses."
        : model?.id || "");
  return result;
}
export function selection(picker, providers, state) {
  const cols = columns(picker, providers, state);
  const provider = cols[0].items.find((p) => p.id === picker.instanceId);
  const model = cols[1].items.find((m) => m.id === picker.model);
  if (!provider || provider.reason || !model?.model || model.reason)
    return null;
  const control = effort(model.model);
  const current = state?.thread?.modelSelection;
  // Unedited traits (fast mode, service tier, context window…) survive only for
  // the same instance/model. Never carry provider-specific options across models.
  const options =
    current?.instanceId === picker.instanceId && current?.model === picker.model
      ? (current.options || []).filter((o) => o.id !== control.descriptor?.id)
      : [];
  const choice = control.items.find((i) => i.id === picker.effort);
  return {
    instanceId: picker.instanceId,
    model: picker.model,
    options: [
      ...(choice ? [{ id: control.descriptor.id, value: choice.id }] : []),
      ...options,
    ],
  };
}
export function input(picker, ch, key, providers, state) {
  if (key.escape || ch === "q") return { picker, action: "close" };
  if (key.return) return { picker: { ...picker, g: false }, action: "apply" };
  let column = picker.column;
  if (key.leftArrow || ch === "h") column = Math.max(0, column - 1);
  if (key.rightArrow || ch === "l") column = Math.min(2, column + 1);
  if (column !== picker.column)
    return { picker: { ...picker, column, g: false } };
  // Ink may deliver a pasted/fast `gg` as one input chunk.
  const top = ch === "gg" || (ch === "g" && picker.g);
  if (ch === "g" && !top) return { picker: { ...picker, g: true } };
  const delta =
    key.upArrow || ch === "k" || (key.ctrl && ch === "p")
      ? -1
      : key.downArrow || ch === "j" || (key.ctrl && ch === "n")
        ? 1
        : 0;
  const next = { ...picker, g: false };
  if (!delta && !top && ch !== "G") return { picker: next };
  const col = columns(picker, providers, state)[column];
  const enabled = col.items.filter((i) => !i.reason);
  const at = enabled.findIndex((i) => i.id === col.value);
  const item =
    enabled[
      top
        ? 0
        : ch === "G"
          ? enabled.length - 1
          : Math.max(0, Math.min(enabled.length - 1, at + delta))
    ];
  if (!item) return { picker: next };
  if (column === 0 && item.id !== picker.instanceId) {
    const choices = models(item.provider, state);
    const current = state?.thread?.modelSelection;
    const model =
      choices.find(
        (m) => item.id === current?.instanceId && m.id === current.model,
      ) ??
      choices.find((m) => m.model?.isDefault) ??
      choices.find((m) => !m.reason);
    Object.assign(next, seed(item, model, state));
  } else if (column === 1 && item.id !== picker.model) {
    Object.assign(next, seed({ id: picker.instanceId }, item, state));
  } else if (column === 2) next.effort = item.id;
  return { picker: next };
}
