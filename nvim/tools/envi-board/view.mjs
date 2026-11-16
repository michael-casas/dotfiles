import stringWidth from "string-width";
import { safeText } from "./document.mjs";

export function viewport(
  lines,
  { width = 80, height = 24, top = 0, left = 0 } = {},
) {
  width = Math.max(1, width);
  height = Math.max(2, height);
  return lines
    .slice(Math.max(0, top), Math.max(0, top) + height - 2)
    .map((line) => {
      let col = 0,
        out = "",
        size = 0;
      for (const { segment } of new Intl.Segmenter(undefined, {
        granularity: "grapheme",
      }).segment(safeText(line).replaceAll("\t", "    "))) {
        const cells = stringWidth(segment);
        if (col >= left && size + cells <= width) {
          out += segment;
          size += cells;
        }
        col += cells;
        if (size >= width) break;
      }
      return out;
    });
}

export function project(
  snapshot,
  { diagrams = new Map(), sourceOnly = false } = {},
) {
  const rows = [],
    mapping = [];
  const push = (line, block) => {
    rows.push(safeText(line));
    mapping.push({
      id: block?.id ?? null,
      kind: block?.kind ?? null,
      line: block?.line ?? 1,
    });
  };
  if (snapshot.stale) push(`STALE: ${snapshot.error}`);
  if (snapshot.watchError) push(snapshot.watchError);
  const doc = snapshot.document;
  if (!doc) {
    push(snapshot.error ?? "Board unavailable");
    return { rows, mapping };
  }
  if (!doc.valid || doc.opaque) {
    push(doc.opaque ? "OPAQUE read-only source" : "INVALID literal source");
    for (const line of doc.bytes.toString().split(/\r?\n/)) push(line);
  } else
    for (const b of doc.blocks) {
      if (b.kind === "mermaid") {
        const render = diagrams.get(b.id);
        push(
          `[diagram ${b.id}: ${render?.kind === "text-approximate" ? "approximate text" : (render?.reason ?? "source; renderer not requested")}]`,
          b,
        );
        if (!sourceOnly && render?.kind === "text-approximate")
          for (const line of render.lines) push(line, b);
        push("Mermaid source:", b);
        for (const line of b.content.split("\n")) push(line, b);
      } else if (b.kind === "wb-thread" && b.record) {
        push(
          `[thread ${b.id}: ${b.record.status}; ${b.attachment}; author/time are claims]`,
          b,
        );
        for (const m of b.record.messages ?? []) {
          push(`${m.author}:`, b);
          for (const line of m.body.split("\n")) push(line, b);
        }
      } else if (b.kind === "wb-source" && b.record) {
        const r = b.record;
        push(`[source ${b.id}] ${r.label ?? ""}`, b);
        push(
          `${r.root}: ${r.path}:${r.lines.start}-${r.lines.end}@${r.commit}`,
          b,
        );
        push(
          "Enter: immutable source (explicit binding required); freshness unknown",
          b,
        );
      } else
        for (const line of b.raw.replace(/\r?\n$/, "").split(/\r?\n/))
          push(line, b);
      push("", b);
    }
  for (const d of snapshot.diagnostics ?? doc.diagnostics)
    push(`[${d.category}/${d.code}] ${d.message}`);
  return { rows, mapping };
}
