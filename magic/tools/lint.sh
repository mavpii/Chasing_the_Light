#!/usr/bin/env bash
#
# lint.sh -- static checks for the magic system.
#
# Every check here exists because the thing it looks for actually broke:
#   * a duplicate catalogue key silently deleted Stasis from the game;
#   * two spell ids in 04x_Southbay had no catalogue entry, so a campaign scenario
#     shipped with a caster whose spells did nothing;
#   * a description referenced icons/illusion.png, which is TDG-only, and the game
#     logged "could not open image" on every draw;
#   * a description line ran past the dialog and was cut off mid-sentence;
#   * an [elseif] added by hand was never closed.
#
# Run from anywhere:   bash magic/tools/lint.sh
# Exit code 0 = clean, 1 = something to look at.
#
# Icon checking needs mainline's data/ for core images. Point WESNOTH_DATA at it,
# e.g. WESNOTH_DATA=/d/Games/wesnoth/data bash magic/tools/lint.sh
# Without it, icons that live in core are reported as "unverified", not as errors.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAGIC="$ROOT/magic"
TABLE="$MAGIC/spells/table.lua"
SPELLS="$MAGIC/spells/spells.cfg"
PROFILES="$MAGIC/ai/ai_profiles.lua"
CORE_IMAGES="${WESNOTH_DATA:-}/core/images"

fails=0
warns=0
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }
fail()    { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
warn()    { printf '  \033[33mWARN\033[0m %s\n' "$1"; warns=$((warns + 1)); }
ok()      { printf '  \033[32mok\033[0m   %s\n' "$1"; }

#---------------------------------------------------------------------------
section "Catalogue keys"
#---------------------------------------------------------------------------
dupes=$(grep -o '^[[:space:]]*\[[0-9]\+\] = {' "$TABLE" | grep -o '[0-9]\+' | sort -n | uniq -d)
if [ -n "$dupes" ]; then
    for k in $dupes; do
        fail "key [$k] is used twice -- Lua keeps the last one and the other spell vanishes"
    done
else
    ok "no duplicate keys ($(grep -c '^[[:space:]]*\[[0-9]\+\] = {' "$TABLE") entries)"
fi

#---------------------------------------------------------------------------
section "Spell ids used by scenarios"
#---------------------------------------------------------------------------
# Comment lines are stripped first: 10_Priorities keeps a long list of planned
# spell ids in comments, and they are notes, not usage. skill_set is the Lua
# table's own field name, not a spell.
grep -vh '^[[:space:]]*#' "$ROOT"/scenarios/*.cfg \
    | grep -oh "skill_[a-z_0-9]*" | grep -v '^skill_set$' | sort -u > /tmp/lint_used.txt
grep -oh 'id *= *"skill_[a-z_0-9]*"' "$TABLE" | sed 's/.*"\(.*\)"/\1/' | sort -u > /tmp/lint_have.txt
# Event names derived from a spell id are not catalogue entries.
missing=$(comm -23 /tmp/lint_used.txt /tmp/lint_have.txt \
    | grep -v '_cast$\|_cast_pre$\|_cast_post$\|_pre$\|_post$\|_cancel$\|_casting$')
if [ -n "$missing" ]; then
    for id in $missing; do
        where=$(grep -l "$id" "$ROOT"/scenarios/*.cfg | head -3 | xargs -n1 basename | tr '\n' ' ')
        fail "$id is not in the catalogue -- used by: $where"
    done
else
    ok "every scenario spell id has a catalogue entry"
fi

#---------------------------------------------------------------------------
section "AI profiles"
#---------------------------------------------------------------------------
grep -o '^[[:space:]]*skill_[a-z_0-9]*' "$PROFILES" | tr -d ' ' | sort -u > /tmp/lint_prof.txt
grep -oh 'id="skill_[a-z_0-9]*"' "$TABLE" | sed 's/.*"\(.*\)"/\1/' | sort -u >> /tmp/lint_have.txt
sort -u /tmp/lint_have.txt -o /tmp/lint_have.txt
orphans=$(comm -23 /tmp/lint_prof.txt /tmp/lint_have.txt)
if [ -n "$orphans" ]; then
    for id in $orphans; do fail "ai_profiles has $id, which is not in the catalogue"; done
else
    ok "every profiled spell exists ($(wc -l < /tmp/lint_prof.txt) profiles)"
fi

#---------------------------------------------------------------------------
section "Icons"
#---------------------------------------------------------------------------
unverified=0; bad_icons=0; checked=0
for img in $(grep -o 'image *= *"[^"]*"' "$TABLE" | sed 's/.*"\(.*\)"/\1/' | sort -u); do
    checked=$((checked + 1))
    if [ -f "$MAGIC/images/$img" ] || [ -f "$ROOT/images/$img" ]; then
        continue
    elif [ -n "${WESNOTH_DATA:-}" ] && [ -f "$CORE_IMAGES/$img" ]; then
        continue
    elif [ -z "${WESNOTH_DATA:-}" ]; then
        unverified=$((unverified + 1))
    else
        fail "$img is referenced by the catalogue but exists nowhere"
        bad_icons=$((bad_icons + 1))
    fi
done
if [ "$unverified" -gt 0 ]; then
    warn "$unverified of $checked icons are not in the add-on; set WESNOTH_DATA to check them against core"
elif [ "$bad_icons" -eq 0 ]; then
    ok "all $checked catalogue icons resolve"
fi

#---------------------------------------------------------------------------
section "Description lines"
#---------------------------------------------------------------------------
# A rich_label with width=0 does not wrap, so anything much past ~90 visible
# characters is cut off at the edge of the dialog.
long=$(grep -h 'description' "$TABLE" | grep -v '^[[:space:]]*--' \
    | sed 's/^[[:space:]]*//; s/^\[[0-9]\+\] = //; s/^description[a-z_]* *= *//' \
    | sed 's/header_[a-z]*()\.\._"//g; s/"\.\.header_[a-z]*()\.\._"//g' \
    | sed 's/^_"//; s/",\?$//' \
    | sed 's/\\n/\n/g' \
    | sed 's/<[^>]*>//g' \
    | sed 's/^[[:space:]]*//' \
    | awk 'length($0) > 92 { printf "%d chars: %.55s...\n", length($0), $0 }')
if [ -n "$long" ]; then
    while IFS= read -r line; do fail "description line too long -- $line"; done <<< "$long"
else
    ok "no description line exceeds 92 visible characters"
fi

#---------------------------------------------------------------------------
section "WML structure (spells.cfg)"
#---------------------------------------------------------------------------
# Some tags are legitimately unbalanced inside this file: a macro opens them and
# the call site closes them (or the other way round). What matters is that the
# difference does not drift, so each is checked against its known delta.
#   #define  +2 : two macros are opened inside other macros' bodies
#   [object] +2 : macros that emit an opening [object] for the caller to close
check_delta() { # name opens closes expected
    if [ $(( $2 - $3 )) -eq "$4" ]; then
        ok "$1 as expected ($2/$3)"
    else
        fail "$1 is $2/$3 -- difference $(( $2 - $3 )), expected $4"
    fi
}
check_delta "#define/#enddef" \
    "$(grep -c '^[[:space:]]*#define' "$SPELLS")" "$(grep -c '^[[:space:]]*#enddef' "$SPELLS")" 2
check_delta "[object]" \
    "$(grep -o '\[object\]' "$SPELLS" | wc -l)" "$(grep -o '\[/object\]' "$SPELLS" | wc -l)" 2
for pair in "if:/if" "then:/then" "elseif:/elseif" "event:/event" "foreach:/foreach"; do
    open="${pair%%:*}"; close="${pair##*:}"
    check_delta "[$open]" "$(grep -o "\[$open\]" "$SPELLS" | wc -l)" "$(grep -o "\[$close\]" "$SPELLS" | wc -l)" 0
done

#---------------------------------------------------------------------------
section "Event registration"
#---------------------------------------------------------------------------
grep -o '^#define EVENT_[A-Z_0-9]*' "$SPELLS" | sed 's/#define //' | sort -u > /tmp/lint_def.txt
sed -n '/^#define MAGIC_SYSTEM__SPELLS_EVENTS$/,/^#define /p' "$SPELLS" \
    | grep -o '{EVENT_[A-Z_0-9]*}' | tr -d '{}' | sort -u > /tmp/lint_reg.txt
unreg=$(comm -23 /tmp/lint_def.txt /tmp/lint_reg.txt | grep -v 'EVENT_REMOVE_SKILLS\|EVENT_BEND_NATURE_REVERT_PRE\|EVENT_SUMMON_CAST\|EVENT_POLYMORPH_TYPE')
if [ -n "$unreg" ]; then
    for m in $unreg; do warn "$m is defined but never expanded in MAGIC_SYSTEM__SPELLS_EVENTS"; done
else
    ok "every spell event macro is registered"
fi

#---------------------------------------------------------------------------
printf '\n'
if [ "$fails" -gt 0 ]; then
    printf '\033[31m%d problem(s)\033[0m, %d warning(s)\n' "$fails" "$warns"
    exit 1
fi
printf '\033[32mclean\033[0m (%d warning(s))\n' "$warns"
exit 0
