# shellcheck shell=bash
# The links phase, sourced by ./install. The only caller of dotbot and
# skill-catalog.py. Bash never creates, compares or removes a link itself:
# dotbot's dry run decides, and its exit code is the conflict gate.

links_configs() {  # the dotbot config files for this OS, one per line
    echo "$CHECKOUT/install.conf.yaml"
    case "$OS" in
        Darwin) echo "$CHECKOUT/install.macos.yaml" ;;
        Linux) echo "$CHECKOUT/install.linux.yaml" ;;
    esac
}

links_check() {    # links_check plan|doctor
    local mode="$1" parent out rc=0 exists pending dead refused unknown shadow state
    local -a configs=()
    while IFS= read -r parent; do configs+=("$parent"); done < <(links_configs)

    if [ -n "${DOTBOT_BIN:-}" ]; then
        report note links "dotbot from DOTBOT_BIN: $DOTBOT"
    else
        state="$(git -C "$CHECKOUT" submodule status dotbot 2>/dev/null | cut -c1)"
        case "$state" in
            " ") report ok links "dotbot submodule at the pinned commit" ;;
            "+") report FAIL links "dotbot submodule is not at the pinned commit; run: git submodule update --init --recursive dotbot"
                 return ;;   # never run an unpinned dotbot
            *) report FAIL links "dotbot submodule is not initialised; run: git submodule update --init --recursive dotbot"
               return ;;
        esac
    fi
    if [ ! -x "$DOTBOT" ]; then
        report FAIL links "dotbot not found at $DOTBOT"
        return
    fi

    # dotbot follows a symlinked directory and would write into its target, so
    # every directory on the way to a destination must be real before it runs.
    if ! out="$(python3 "$CHECKOUT/install.d/parents.py" "$DOTBOT" "$BASE" "${configs[@]}" 2>&1)"; then
        while IFS=$'\t' read -r state parent; do
            case "$state" in
                symlink) report FAIL links "$parent is a symlink; managed directories must be real (nothing was run)" ;;
                "not a directory") report FAIL links "$parent is not a directory; managed directories must be real (nothing was run)" ;;
                *) report FAIL links "could not check the managed directories: $state $parent" ;;
            esac
        done < <(printf '%s\n' "$out")
        return
    fi

    # -v adds the "Link exists" lines, which are counted, not shown.
    out="$("$DOTBOT" -v --no-color -d "$BASE" --dry-run --only link create clean -c "${configs[@]}" 2>&1)" || rc=$?
    exists="$(printf '%s\n' "$out" | grep -c '^Link exists ' || true)"
    pending="$(printf '%s\n' "$out" | grep -c '^Would create symlink ' || true)"
    dead="$(printf '%s\n' "$out" | grep -c '^Would remove invalid link ' || true)"
    # The pinned dotbot's conflict lines (plugins/link.py). Anything that is
    # neither one of them nor a known progress line is an error, and wins.
    refused="$(printf '%s\n' "$out" | grep -c -e ' already exists but is a regular file or directory$' \
        -e '^Incorrect link ' -e '^Invalid link ' || true)"
    out="$(printf '%s\n' "$out" | grep -v -e '^Link exists ' -e '^All .* successfully$' -e '^All .*been .*$' \
        -e '^Some .* successfully' -e ' not removed\.$' -e '^$' || true)"
    unknown="$(printf '%s\n' "$out" | grep -c -v -e '^Would create ' -e '^Would remove invalid link ' \
        -e ' already exists but is a regular file or directory$' -e '^Incorrect link ' -e '^Invalid link ' \
        -e '^$' || true)"
    report ok links "$exists declared links in place (base $BASE)"
    if [ "$rc" -ne 0 ] && [ "$refused" -gt 0 ] && [ "$unknown" -eq 0 ]; then
        CONFLICTS=$((CONFLICTS + 1))
        report CONFLICT links "dotbot refuses $refused links and would create $pending; each is listed below, nothing is touched"
    elif [ "$rc" -ne 0 ]; then
        report FAIL links "dotbot could not plan the links (exit $rc, $refused conflicts, $unknown other errors); its output is below"
    elif [ "$pending" -gt 0 ] || [ "$dead" -gt 0 ]; then
        if [ "$mode" = doctor ]; then state=FAIL; else state=plan; fi
        report "$state" links "$pending links to create, $dead dead links to remove"
    fi
    if [ -n "$out" ]; then printf '%s\n' "$out" | detail; fi

    # Ghostty on macOS loads these after the XDG file, so they win.
    if [ "$OS" = Darwin ]; then
        for shadow in config config.ghostty; do
            shadow="$HOME/Library/Application Support/com.mitchellh.ghostty/$shadow"
            if [ -e "$shadow" ] || [ -L "$shadow" ]; then
                if [ "$mode" = doctor ]; then state=FAIL; else state=warn; fi
                report "$state" ghostty "$shadow loads after the XDG config and overrides it; fold it into ghostty/config, then move it aside"
            fi
        done
    fi

    if [ -f "$BASE/skill-catalog.py" ]; then
        out="$(python3 "$BASE/skill-catalog.py" 2>/dev/null | python3 -c 'import json, sys
d = json.load(sys.stdin)
print(d["sources"], d["links_needed"], len(d["skipped_user_owned"]), len(d["retired_links"]))')" || {
            report FAIL skills "skill-catalog.py could not plan"
            return
        }
        local sources needed kept retired
        # Process substitution, not a here-string: Bash 3.2 writes those to a temp file.
        read -r sources needed kept retired < <(printf '%s\n' "$out")
        if [ "$needed" -eq 0 ] && [ "$retired" -eq 0 ]; then report ok skills "$sources skills linked"
        elif [ "$mode" = doctor ]; then report FAIL skills "$needed skill links to create, $retired retired links to remove"
        else report plan skills "$needed skill links to create, $retired retired links to remove"; fi
        if [ "$kept" -gt 0 ]; then report warn skills "$kept skill destinations are user-owned and kept (python3 skill-catalog.py lists them)"; fi
    fi
}
