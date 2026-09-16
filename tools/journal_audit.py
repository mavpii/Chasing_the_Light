#!/usr/bin/env python3
"""Audit the JourneyLog content of Chasing the Light.

Run from anywhere:

    python tools/journal_audit.py

Checks performed:

  chapters    every scenario registers a {JOURNAL} chapter and its id matches
              the scenario's own id=
  milestones  every milestone a journal entry is gated on is actually unlocked
              somewhere in WML, and every unlocked milestone is used by an entry
  entries     how much of journey/profiles.cfg and journey/world.cfg is still
              a TODO placeholder

Milestone unlocks are resolved through macros, so {CTL_NOTE s6_arvit ...} counts
as unlocking s6_arvit even though the {MILESTONE} call lives inside the macro
body. Any future wrapper macro is picked up the same way, with no change here.

Exit status is 1 when a problem is reported, 0 when the journal is clean.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PREPROCESSOR_WORDS = (
    "define", "enddef", "undef", "ifdef", "ifndef", "ifhave", "ifnhave",
    "ifver", "ifnver", "else", "elseif", "endif", "textdomain",
)

UNUSED_MARKER = "scenarios/unused/"


# ---------------------------------------------------------------------------
# generic WML/preprocessor helpers
# ---------------------------------------------------------------------------

def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def cfg_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", "translations")]
        for name in sorted(files):
            if name.endswith(".cfg"):
                yield os.path.join(base, name)


def is_comment(line):
    stripped = line.lstrip()
    if not stripped.startswith("#"):
        return False
    rest = stripped.lstrip("#").strip()
    return not any(rest.startswith(word) for word in PREPROCESSOR_WORDS)


def without_comments(text):
    kept = []
    for line in text.split("\n"):
        kept.append("" if is_comment(line) else line)
    return "\n".join(kept)


def split_macro_args(text, start):
    """Split the arguments of a macro call whose name ends at `start`.

    Respects quoted strings, (...) argument groups and nested {...} calls, so a
    note body containing braces or spaces stays a single argument.
    """
    args, buf, depth, quoted = [], "", 0, False
    i = start
    while i < len(text):
        char = text[i]
        if quoted:
            buf += char
            if char == '"':
                quoted = False
            i += 1
            continue
        if char == '"':
            quoted = True
            buf += char
        elif char in "({":
            depth += 1
            buf += char
        elif char == ")":
            depth -= 1
            buf += char
        elif char == "}":
            if depth == 0:
                if buf.strip():
                    args.append(buf.strip())
                return args, i
            depth -= 1
            buf += char
        elif char.isspace() and depth == 0:
            if buf.strip():
                args.append(buf.strip())
            buf = ""
        else:
            buf += char
        i += 1
    if buf.strip():
        args.append(buf.strip())
    return args, len(text)


def find_calls(text, macro_name):
    """Yield (args, line_number) for every {MACRO_NAME ...} call in text."""
    pattern = re.compile(r"\{%s(?=[\s}])" % re.escape(macro_name))
    for match in pattern.finditer(text):
        args, _ = split_macro_args(text, match.end())
        yield args, text.count("\n", 0, match.start()) + 1


# ---------------------------------------------------------------------------
# milestone unlock resolution
# ---------------------------------------------------------------------------

def macro_definitions():
    """Map macro name -> (parameter list, body) for every #define in the add-on."""
    definitions = {}
    for path in cfg_files():
        text = read(path)
        for match in re.finditer(r"#define[ \t]+(\w+)([^\n]*)\n(.*?)#enddef", text, re.S):
            definitions[match.group(1)] = (match.group(2).split(), match.group(3))
    return definitions


def milestone_macros(definitions):
    """Find every macro that ends up unlocking a milestone.

    Returns name -> list of either ('arg', index) or ('literal', milestone_id).
    Resolved to a fixed point so a wrapper around a wrapper is still caught.
    """
    unlockers = {"MILESTONE": [("arg", 0)]}
    for _ in range(5):
        grew = False
        for name, (params, body) in definitions.items():
            if name in unlockers:
                continue
            sources = []
            for inner, calls in list(unlockers.items()):
                for args, _line in find_calls(body, inner):
                    for kind, key in calls:
                        if kind == "literal":
                            sources.append(("literal", key))
                            continue
                        if key >= len(args):
                            continue
                        value = args[key]
                        placeholder = re.fullmatch(r"\{(\w+)\}", value)
                        if placeholder and placeholder.group(1) in params:
                            sources.append(("arg", params.index(placeholder.group(1))))
                        elif re.fullmatch(r"[A-Za-z0-9_]+", value):
                            sources.append(("literal", value))
            if sources:
                unlockers[name] = sources
                grew = True
        if not grew:
            break
    return unlockers


def collect_unlocks(unlockers):
    """Map milestone id -> list of 'path:line' where it gets unlocked."""
    unlocked = {}
    for path in cfg_files():
        text = without_comments(read(path))
        if rel(path) == "utils/macros.cfg":
            # Only macro definitions live here, calls inside them are not unlocks.
            text = re.sub(r"#define[ \t]+\w+[^\n]*\n.*?#enddef", "", text, flags=re.S)
        for name, calls in unlockers.items():
            for args, line in find_calls(text, name):
                for kind, key in calls:
                    if kind == "literal":
                        value = key
                    elif key < len(args):
                        value = args[key]
                    else:
                        continue
                    if re.fullmatch(r"[A-Za-z0-9_]+", value):
                        unlocked.setdefault(value, []).append("%s:%d" % (rel(path), line))
        for match in re.finditer(r"\[unlock_milestone\](.*?)\[/unlock_milestone\]", text, re.S):
            found = re.search(r"milestone=([A-Za-z0-9_,]+)", match.group(1))
            if found:
                line = text.count("\n", 0, match.start()) + 1
                for value in found.group(1).split(","):
                    unlocked.setdefault(value.strip(), []).append("%s:%d" % (rel(path), line))
    return unlocked


# ---------------------------------------------------------------------------
# journal content
# ---------------------------------------------------------------------------

def journal_entries():
    """Parse journey/*.cfg into a list of entry dicts."""
    entries = []
    for name in ("profiles.cfg", "world.cfg"):
        path = os.path.join(ROOT, "journey", name)
        if not os.path.exists(path):
            continue
        text = read(path)
        for tag in ("character_profile", "world_entry"):
            pattern = r"^([ \t]*)\[%s\](.*?)^\1\[/%s\]" % (tag, tag)
            for match in re.finditer(pattern, text, re.S | re.M):
                body = match.group(2)
                line = text.count("\n", 0, match.start()) + 1
                stages = [("", body.split("[additional_info]")[0])]
                for extra in re.findall(r"\[additional_info\](.*?)\[/additional_info\]", body, re.S):
                    gate = re.search(r"^[ \t]*requires_milestone=(\S+)", extra, re.M)
                    stages.append((gate.group(1) if gate else "?", extra))
                base_gate = re.search(r"^[ \t]*requires_milestone=(\S+)", stages[0][1], re.M)
                if base_gate:
                    stages[0] = (base_gate.group(1), stages[0][1])
                entry_id = re.search(r"^[ \t]*id=(\S+)", body, re.M)
                entries.append({
                    "kind": tag,
                    "id": entry_id.group(1) if entry_id else "?",
                    "file": rel(path),
                    "line": line,
                    "stages": stages,
                })
    return entries


def commented_gates():
    out = []
    for name in ("profiles.cfg", "world.cfg"):
        path = os.path.join(ROOT, "journey", name)
        if not os.path.exists(path):
            continue
        for number, line in enumerate(read(path).split("\n"), 1):
            if is_comment(line) and "requires_milestone=" in line:
                gate = re.search(r"requires_milestone=(\S+)", line)
                if gate:
                    out.append((gate.group(1), "%s:%d" % (rel(path), number)))
    return out


def scenario_chapters():
    """Return (filename, scenario id, JOURNAL id, is_unused) per scenario file."""
    rows = []
    for path in cfg_files():
        name = rel(path)
        if not name.startswith("scenarios/"):
            continue
        text = read(path)
        if "[scenario]" not in text and "[multiplayer]" not in text:
            continue
        start = min(i for i in (text.find("[scenario]"), text.find("[multiplayer]")) if i >= 0)
        scenario_id = re.search(r"^[ \t]*id=(\S+)", text[start:], re.M)
        journal = re.search(r"\{JOURNAL[ \t]+(\S+)", text)
        rows.append((
            name,
            scenario_id.group(1) if scenario_id else None,
            journal.group(1) if journal else None,
            UNUSED_MARKER in name,
        ))
    return rows


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

class Report:
    def __init__(self):
        self.problems = 0

    def section(self, title):
        print()
        print(title)
        print("-" * len(title))

    def ok(self, message):
        print("  ok    %s" % message)

    def warn(self, message):
        self.problems += 1
        print("  WARN  %s" % message)


def audit():
    report = Report()
    definitions = macro_definitions()
    unlockers = milestone_macros(definitions)
    unlocked = collect_unlocks(unlockers)
    entries = journal_entries()

    required = {}
    for entry in entries:
        for gate, _body in entry["stages"]:
            if gate and gate != "?":
                required.setdefault(gate, []).append("%s (%s:%d)" % (entry["id"], entry["file"], entry["line"]))

    # -- chapters ----------------------------------------------------------
    report.section("Chapters")
    for name, scenario_id, journal_id, unused in scenario_chapters():
        tag = " [unused]" if unused else ""
        if journal_id is None:
            if scenario_id and scenario_id.startswith(("99_", "MP_")):
                report.ok("%s has no {JOURNAL}, not a story scenario" % name)
            else:
                report.warn("%s has no {JOURNAL} chapter%s" % (name, tag))
        elif journal_id != scenario_id:
            report.warn("%s: {JOURNAL %s} does not match id=%s, its log will not show%s"
                        % (name, journal_id, scenario_id, tag))
        else:
            report.ok("%s -> %s%s" % (name, journal_id, tag))

    # -- milestones --------------------------------------------------------
    report.section("Milestones")
    wrappers = sorted(n for n in unlockers if n != "MILESTONE")
    print("  resolved through: MILESTONE, [unlock_milestone]%s"
          % ("".join(", " + n for n in wrappers)))
    print("  required by journal: %d   unlocked in WML: %d" % (len(required), len(unlocked)))
    print()

    for gate in sorted(required):
        where = unlocked.get(gate)
        if not where:
            report.warn("%-24s gated but never unlocked -> %s" % (gate, ", ".join(required[gate])))
        elif all(UNUSED_MARKER in place for place in where):
            report.warn("%-24s only unlocked in an unused scenario (%s) -> %s"
                        % (gate, ", ".join(where), ", ".join(required[gate])))

    for gate in sorted(unlocked):
        if gate not in required:
            report.warn("%-24s unlocked but no journal entry uses it -> %s"
                        % (gate, ", ".join(unlocked[gate])))

    for gate, place in commented_gates():
        report.warn("%-24s gate is commented out at %s" % (gate, place))

    if report.problems == 0:
        report.ok("every gate lines up")

    # -- entries -----------------------------------------------------------
    report.section("Entries")
    todo_total = 0
    for kind, label in (("character_profile", "characters"), ("world_entry", "world lore")):
        group = [e for e in entries if e["kind"] == kind]
        print("  %s: %d entries, %d stages" % (label, len(group), sum(len(e["stages"]) for e in group)))
    print()
    print("  %-18s %-7s %s" % ("entry", "stages", "stages still TODO"))
    for entry in entries:
        todo = [gate or "(base)" for gate, body in entry["stages"] if "TODO" in body]
        todo_total += len(todo)
        if todo:
            print("  %-18s %-7d %s" % (entry["id"], len(entry["stages"]), ", ".join(todo)))
    print()
    print("  %d stages still hold a TODO placeholder" % todo_total)
    if todo_total:
        print("  note: description= is an extend attribute, stages are concatenated with a")
        print("        blank line, so a stage that needs no new paragraph can simply drop it")

    # -- summary -----------------------------------------------------------
    report.section("Summary")
    print("  %d problem(s)" % report.problems)
    return 1 if report.problems else 0


if __name__ == "__main__":
    sys.exit(audit())
