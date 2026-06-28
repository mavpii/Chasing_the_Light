# Magic System — Reference

> Last updated to match the 4-file refactor: `state.lua`, `ops.lua`, `dialog.lua`, `core.lua`.

---

## Architecture

The system is split into four Lua files loaded by `utils.cfg`:

```
utils.cfg
  └─ [lua] wesnoth.require 'magic/core.lua'
                ├─ wesnoth.require 'state.lua'   (Layer 1: WML ↔ Lua)
                ├─ wesnoth.require 'ops.lua'     (Layer 2: pure functions)
                ├─ wesnoth.require 'dialog.lua'  (Layer 3: UI)
                └─ wesnoth.require 'table.lua'   (read-only spell catalogue)
```

**state.lua** — only file that touches WML variables. `CasterState.load(id)` reads all variables into a plain Lua table; `CasterState.save(data)` writes it back. This is the sync boundary: WML variables auto-sync between multiplayer clients, Lua tables do not.

**ops.lua** — pure functions operating on the Lua data table returned by `load`. No WML reads or writes, no unit lookups. Every function mutates the table in place; the caller saves it when done.

**dialog.lua** — builds the WML dialog structure, wires interactivity in a preshow callback, and orchestrates `evaluate_single` / `invoke_command` for multiplayer safety.

**core.lua** — thin entry point. Defines all `wml_actions`, the caster registry, the double-click handler, and `open_for_unit`.

---

## Multiplayer model

| What | Where runs | Sync mechanism |
|---|---|---|
| GUI (dialog) | Local client only | `wesnoth.sync.evaluate_single` |
| Costs (XP/HP/Gold/ATK) | All clients | `wesnoth.sync.invoke_command("spellcasting_cost", …)` |
| Casts-per-turn counter | All clients | `casts_increment=true` flag in `spellcasting_cost` |
| Spell selection picker | Local client only | `gui.show_dialog` inside `evaluate_single`; choice via shared Lua table |
| Commit selection + re-apply abilities | All clients | `wesnoth.sync.invoke_command("magic_commit", {id, equipped, wait})` |
| Cast a chosen spell | All clients | `do_command{ custom_command=magic_set_caster; fire_event=<spell id> }` after `evaluate_single` |
| All other caster state | All clients | WML variables (auto-synced) |

**Committing a selection.** The selection/picker dialog only *collects* the player's choice into
a shared Lua table (`choice`); it does **not** write any game state. On Confirm, the button
handler calls `wesnoth.sync.invoke_command("magic_commit", { id = caster.id, equipped = ..., wait = ... })`
from **inside** the button click — this is the one place in `gui.show_dialog` it's safe to call
`invoke_command`, since the dialog is always opened from an unsynced context (right-click menu,
double-click, or RESELECT deferred to a mouse move; see `core.lua`'s `magic_commit`/`magic_apply_selection`).
`magic_commit` runs on every client: it sets `current_caster`, calls `[magic_apply_selection]`
directly (passing `equipped`/`wait` as **command parameters**, not WML variables) to write the
equipped/group variables (calling `assign_free` in free-assign mode) and fire `refresh_skills`,
then fires `magic_sync_flush` ([disallow_undo]) so the change reaches other clients immediately
instead of waiting on the undo stack.

`[magic_apply_selection]` refuses to apply an **empty** spell list, so a glitch upstream can
never wipe a caster's groups/equipped.

**Why parameters, not a WML variable hand-off.** An earlier design tried
`do_command{ [set_variable] current_caster=<id>; [fire_event] magic_commit_selection }`, reading
`current_caster`/`equipped` back from WML variables inside the `magic_commit_selection` event.
This silently delivered an **empty** equipped list: `[set_variable]` is not in `[do_command]`'s
`allowed_tags` (engine-side: `src/game_events/action_wml.cpp`, the `do_command` WML handler only
honors `attack`, `move`, `recruit`, `recall`, `disband`, `fire_event`, `custom_command` — anything
else is logged as `"unsupported tag"` and dropped). The variable write never happened, so the
fired event read stale/empty data. Passing the data as **custom_command parameters** (what
`wesnoth.sync.invoke_command` does under the hood — see `intf_invoke_synced_command` in
`game_lua_kernel.cpp`) sidesteps this entirely, since `custom_command` *is* an allowed tag.
The cast path (`dialog.lua`'s cast-mode button handler) hit the exact same trap for
`current_caster` specifically — fixed the same way, by wrapping the `magic_set_caster` call as a
`[custom_command]` child alongside `[fire_event]` instead of a bare `[set_variable]`.

**Rule:** never write game-affecting state inside `evaluate_single` without going through
`invoke_command`. WML variable writes inside `evaluate_single` are local-only. And never put a
bare `[set_variable]` inside `[do_command]` — it is not an allowed tag and is silently dropped;
use `[custom_command]` (or `invoke_command`) to carry data into a synced action instead.

---

## Caster state fields

All stored as WML variables under the prefix `caster_<unit_id>.*`.

| Field | WML variable suffix | Type | Notes |
|---|---|---|---|
| `id` | *(key)* | string | Unit ID |
| `title_select` | `.u_title_select` | string | Dialog title in selection mode |
| `title_cast` | `.u_title_cast` | string | Dialog title in cast mode |
| `description` | `.u_description` | string | Shown in dialog header |
| `unlocked` | `.spell_unlocked` | comma-list | Spells the caster can equip |
| `equipped` | `.spell_equipped` | comma-list | Currently active spells (one per group) |
| `groups[i]` | `.spell_group_1` … `.spell_group_10` | comma-list | Spell pool per slot |
| `spellcasting_disabled` | `.utils_spellcasting_allowed` | `"disabled"` / nil | Hides right-click menu |
| `advancement_disabled` | `.utils_advancement_allowed` | `"disabled"` / nil | Hides advance button |
| `polymorphed` | `.polymorphed` | any / nil | Blocks casting while set |
| `wait_to_select` | `.wait_to_select_spells` | `"yes"` / nil | Forces selection mode on next open |
| `reselect_free` | `.reselect_free` | `true` / nil | Upgrade: shows "Change Spells" button |
| `max_casts` | `.max_casts` | number (≥1) | Upgrade: casts allowed per turn |
| `casts_this_turn` | `.casts_this_turn` | number | Counter reset each turn start |
| `free_assign` | `.free_assign` | `true` / nil | Upgrade: pick any spell into any slot |
| `free_unlocked` | `.free_unlocked` | `true` / nil | Upgrade: free-pick — same UI as free_assign, restricted to unlocked spells |

The `caster_registry` WML variable holds a comma-list of all registered unit IDs. It lets `caster_set_menu` iterate only active casters instead of scanning the full unit list.

---

## WML tags (wml_actions)

### `[assign_caster]`
Registers a unit as a caster and builds its initial state.

```cfg
[assign_caster]
    [filter]
        id=Haralin
    [/filter]
    title_select  = "Select Haralin's Spells"
    title_cast    = "Cast Haralin's Spells"
    description   = "..."          # optional, auto-generated if omitted
    spell_group_1 = "fireball,firebolt"
    spell_group_2 = "heal,greater_heal"
    unlocked_spells = "fireball,heal"
    equipped_spells = "fireball,heal"
    spellcasting_allowed = yes      # optional, default yes
[/assign_caster]
```

### `[modify_caster]`
Updates fields on an existing caster (or calls `assign_caster` if the unit has no state yet). Only fields present in the tag are changed.

### `[remove_caster]`
Removes all WML state and the right-click menu for a unit.

### `[unlock_spell]`
Makes one or more spells available to equip. Comma-separated.

```cfg
[unlock_spell]
    [filter] id=Haralin [/filter]
    spell_id = icebolt,icewall
[/unlock_spell]
```

### `[lock_spell]`
Removes a spell from the unlocked pool and unequips it if active.

### `[equip_spell]` / `[unequip_spell]`
Directly set the equipped spell for a group slot. `equip_spell` replaces whatever was equipped in the same group.

### `[find_equipped_spell]`
Writes `true`/`false` to WML variable `equipped_spell_found`.

```cfg
[find_equipped_spell]
    [filter] id=Haralin [/filter]
    spell_id = fireball
[/find_equipped_spell]
[if]
    [variable] name=equipped_spell_found op=equals value=true [/variable]
    ...
[/if]
```

### `[find_unlocked_spell]`
Same but checks the unlocked pool (not just equipped). Also writes to `equipped_spell_found` for backwards compatibility with `spells.cfg`.

### `[caster_status]`
Enable or disable spellcasting (shows/hides the right-click menu item).

```cfg
[caster_status]
    [filter] id=Haralin [/filter]
    spellcasting_allowed = no   # or yes
[/caster_status]
```

### `[caster_advance]`
Show or hide the advancement button in the cast dialog.

```cfg
[caster_advance]
    [filter] id=Haralin [/filter]
    advancement_allowed = yes
[/caster_advance]
```

### `[caster_reselect]` *(upgrade)*
Enables the "Change Spells" button inside the cast dialog. When clicked the dialog closes and immediately reopens in selection mode. Does nothing unless `reselect_allowed=yes`.

```cfg
[caster_reselect]
    [filter] id=Haralin [/filter]
    reselect_allowed = yes   # or no to remove
[/caster_reselect]
```

### `[caster_max_casts]` *(upgrade)*
Sets how many spells the caster may cast per turn. Default is 1. When `max_casts > 1`, a "X/N casts remaining" counter appears at the bottom of the cast dialog.

```cfg
[caster_max_casts]
    [filter] id=Haralin [/filter]
    max_casts = 2
[/caster_max_casts]
```

The counter is tracked via the synced command `spellcasting_cost` (flag `casts_increment=true`) and reset to 0 at `turn refresh` / `start`.

### `[caster_restore_casts]`
Gives back casts already spent this turn. With no `count`, fully restores (back to 0 spent). With `count`, restores only that many — floored at 0 spent, so it can never grant casts beyond what was actually used. Used internally by `TRSS.cfg` to refund the cast when a targeted spell is cancelled (the dialog already incremented `casts_this_turn` before targeting started); also useful in scenario scripts that script a "failed attempt" but want the caster to retry the same turn.

```cfg
[caster_restore_casts]
    [filter] id=Haralin [/filter]
    count = 1   # optional; omit for a full restore
[/caster_restore_casts]
```

### `[caster_free_assign]` *(upgrade)*
Enables or disables free-assign mode. When enabled, the **selection dialog** no
longer offers a fixed per-group menu; instead every slot becomes a clickable
cell. Clicking a slot's image/name opens a **picker grid** of every spell in the
catalogue. Hovering a spell shows its description and cost; clicking one closes
the picker and drops that spell into the slot. On confirm, each slot's pick is
unlocked, equipped, and turned into its own one-spell group, so cast mode and
`refresh_skills` keep working unchanged.

```cfg
[caster_free_assign]
    [filter] id=Haralin [/filter]
    free_assign_allowed = yes   # or no to remove
[/caster_free_assign]
```

Slot count equals the caster's current number of `spell_group_N` entries.

### `[caster_free_unlocked]` *(upgrade — free-pick)*
Enables or disables **free-pick** mode. This is the free-assign UI (one clickable
slot per group, opening a picker grid), but the picker is **restricted to the
caster's unlocked spells** instead of the full catalogue. The player can freely
place any *unlocked* spell into any slot.

```cfg
[caster_free_unlocked]
    [filter] id=Haralin [/filter]
    free_unlocked_allowed = yes   # or no to remove
[/caster_free_unlocked]
```

If both `free_assign` and `free_unlocked` are set, `free_assign` wins (full
catalogue), since it is the strict superset. Commit flows through
`[magic_apply_selection]` exactly like free-assign (`assign_free`), so cast mode
and `refresh_skills` are unchanged.

### `[refresh_skills]`
Re-fires the `refresh_skills` WML event which causes `spells.cfg` to add/remove unit abilities matching the current equipped list. Called automatically after equip/unequip changes.

```cfg
[refresh_skills]
    id=Haralin
[/refresh_skills]
```

### `[refresh_caster_animations]`
Removes and re-adds the unit ability object that carries combat animations. Call after a unit changes its sprite (polymorph, advancement).

### `[caster_set_menu]`
Rebuilds right-click menu items for all registered casters on the current side. Called automatically on turn start and after state changes.

### `[select_caster_skills]`
Opens the spell selection dialog for the matching unit(s). Forces selection mode regardless of `wait_to_select`.

### `[show_caster_skills]`
Opens the spell dialog in cast mode (or selection mode if `wait_to_select` is set).

### `[cast_spell]` *(command-driven cast)*
Casts a **normal** (self/automatic) spell from WML, without opening the dialog —
for cutscenes, AI, or scripted events. Sets `current_caster`, deducts the spell's
catalogue cost, and fires the spell's event.

```cfg
[cast_spell]
    [filter] id=Haralin [/filter]   # the caster
    spell_id = skill_shield
    free            = no   # optional: yes = no cost
    require_unlocked = no  # optional: yes = skip unless caster has it unlocked
    require_equipped = no  # optional: yes = skip unless equipped
    count_cast      = no   # optional: yes = also spend one of the per-turn casts
[/cast_spell]
```

The spell's effect must be defined as `[event name=<spell_id>]` (as in `spells.cfg`).
For a TRSS spell, `[cast_spell]` would start the interactive click-to-target flow;
use `[cast_targeted_spell]` instead to target a hex directly.

### `[cast_targeted_spell]` *(command-driven TRSS cast)*
Fires a TRSS spell's `"<spell_id>_cast"` effect **directly on a chosen hex**,
skipping the interactive targeting. Sets `current_caster`, `unit_to_modify_x/y`
(caster), `unit_to_cast_on_x/y` (target), and `distance_between_units`, then fires
`<spell_id>_cast` and `<spell_id>_cast_post`.

```cfg
[cast_targeted_spell]
    [filter] id=Haralin [/filter]       # the caster
    spell_id = skill_summon_mud         # cast_event defaults to skill_summon_mud_cast
    target_x,target_y = 12,9            # OR a [target] unit filter (below)
    # [target] id=SomeEnemy [/target]
    cast_event = ...   # optional override of the fired event name
    free = no          # same optional flags as [cast_spell]
[/cast_targeted_spell]
```

Works for **adjacent** and **ranged** TRSS effects (their whole effect lives in the
`_cast` event). The **rose** spells (`skill_bend_*`) keep extra logic — unit
push, lava damage — inside the interactive click handler, so a direct cast only
runs their per-hex `_cast` body, not those extras.

---

## WML macros

| Macro | Delegates to | Notes |
|---|---|---|
| `{RESELECT_SKILLS (id=X)}` | `[select_caster_skills]` | Force spell selection |
| `{RESELECT_SKILLS_AFTER_OBJECTIVES (id=X) () ()}` | mouse/select events | Open selection after objectives screen |
| `{REFRESH_CASTER_ANIMATIONS (id=X)}` | `[refresh_caster_animations]` | After polymorph etc. |
| `{UNLOCK_SPELL (id=X) spell_id}` | `[unlock_spell]` | |
| `{LOCK_SPELL (id=X) spell_id}` | `[lock_spell]` | |
| `{CASTER_STATUS (id=X) yes/no}` | `[caster_status]` | |
| `{CASTER_ADVANCE (id=X) yes/no}` | `[caster_advance]` | |
| `{EQUIP_SPELL (id=X) spell_id}` | `[equip_spell]` | |
| `{UNEQUIP_SPELL (id=X) spell_id}` | `[unequip_spell]` | |
| `{CHECK_EQUIPPED_SPELL (id=X) spell_id}` | `[find_equipped_spell]` | Sets `equipped_spell_found` |
| `{CHECK_UNLOCKED_SPELL (id=X) spell_id}` | `[find_unlocked_spell]` | Sets `equipped_spell_found` |
| `{REMOVE_CASTER (id=X)}` | `[remove_caster]` | |
| `{CASTER_RESELECT (id=X) yes/no}` | `[caster_reselect]` | Upgrade: free reselect |
| `{CASTER_MAX_CASTS (id=X) N}` | `[caster_max_casts]` | Upgrade: multi-cast |
| `{CASTER_RESTORE_CASTS (id=X)}` | `[caster_restore_casts]` | Fully restore casts spent this turn |
| `{CASTER_RESTORE_CASTS_COUNT (id=X) N}` | `[caster_restore_casts]` | Restore N casts spent this turn |
| `{CASTER_FREE_ASSIGN (id=X) yes/no}` | `[caster_free_assign]` | Upgrade: any spell in any slot |
| `{CASTER_FREE_UNLOCKED (id=X) yes/no}` | `[caster_free_unlocked]` | Upgrade: free-pick — any unlocked spell in any slot |
| `{CAST_SPELL (id=X) spell_id}` | `[cast_spell]` | Command-cast a normal spell (with cost) |
| `{CAST_SPELL_FREE (id=X) spell_id}` | `[cast_spell]` | Command-cast a normal spell (no cost) |
| `{CAST_TARGETED_SPELL (id=X) spell_id X Y}` | `[cast_targeted_spell]` | Command-cast a TRSS spell on hex X,Y (with cost) |
| `{CAST_TARGETED_SPELL_FREE (id=X) spell_id X Y}` | `[cast_targeted_spell]` | Command-cast a TRSS spell on hex X,Y (no cost) |
| `{CASTER_AI side score}` | `[modify_ai]` + `ai.lua` | Adaptive AI: caster auto-picks the best of its own equipped spells |
| `{CASTER_AI_SPELL side spell range mode score}` | `[modify_ai]` + `ai.lua` | Adaptive AI: cast a specific targeted spell at the best enemy in range |
| `{CASTER_AI_SPELL_SELF side spell score}` | `[modify_ai]` + `ai.lua` | Adaptive AI: self-cast a specific spell (shield, stasis, …) |

---

## Adaptive AI casting

`magic/ai.lua` lets an **AI side use its casters' spells** as part of its normal
decision loop (not scripted turn events). It registers a Lua `[candidate_action]`
whose `eval`/`exec` call into `ai.lua`; the cast goes through the same
`[cast_spell]` / `[cast_targeted_spell]` tags. There are two ways to wire it up.

### Autonomous — the caster chooses (recommended)

One macro for the whole side. Each AI caster looks at **its own equipped spells**
(`data.equipped`) and picks the most useful one for the current board:

```cfg
{CASTER_AI 3 95000}   # side 3, candidate-action score ~95000
```

Which spell it picks is decided by the editable catalogue **`magic/ai_profiles.lua`**
— one line per castable spell. **Add a line to enable a spell for the AI, delete a
line to disable it.** Each entry declares a `kind` (and a few numbers); the engine
in `ai.lua` knows how to value and target each kind:

```lua
return {
    skill_disattack = { kind="damage",    range=6, power=27, base=20 }, -- zap an enemy
    skill_smite     = { kind="aoe_self",  radius=1, power=30, base=15 }, -- hit adjacent foes
    skill_disheal   = { kind="heal_target", range=7, base=15 },         -- heal a wounded ally
    skill_shield    = { kind="buff_self", threat=3, weight=12, base=20 },-- guard when threatened
    skill_summon    = { kind="summon", cast="skill_summon_mud", threat=4 },
    ...
}
```

Kinds: `damage`, `aoe_self` (radius around caster, `ally_penalty` for friendly
splash), `heal_target`, `heal_self_aura`, `buff_self`, `buff_team`, `debuff_aura`
(`vs_casters=true` for counterspell), `summon`. Each turn the AI scores every
profiled, **affordable** spell the caster has equipped and casts the single
highest-utility one — so it zaps in range, heals a hurt ally, shields when cornered,
smites a cluster, etc. The shipped catalogue covers **every castable spell and every
subskill** — damage (disattack), summons (all five), bend (all four), polymorph (all
four forms), smite, nature's revenge, blizzard, cataclysm, disheal, massheal,
panacea, shield, levitate, flight, stasis, counterspell, illusion, time dilation,
swap, ward. Equipping the **parent** (Summon/Bend/Polymorph) auto-expands to its
subskills, and the AI picks the strongest one it can afford. A few carry caveats
(bend's push/lava extras live in the interactive handler; stasis petrifies the
caster; panacea kills the healed ally next turn) — noted in `ai_profiles.lua`. The
only spell that can't be auto-cast is `skill_relocate` (two interactive steps).
Profiles can also be tweaked at runtime with `ai.lua`'s `set_profile`/`forget_profile`.

### Explicit — you pick the spell + rule

Lower-level: register one candidate action per spell with a fixed targeting rule
and score (useful for forcing a specific behaviour):

```cfg
{CASTER_AI_SPELL 3 skill_disattack 6 nearest 95000}  # targeted: nearest|weakest in range
{CASTER_AI_SPELL_SELF 3 skill_shield 95000}          # self-cast
```

### Common behaviour

AI casts are **charged by default** (xp/hp/gold/attack, from `table.lua`), and the
AI never picks a spell the caster cannot afford. Casts always count against
`max_casts` — so a caster fires at most `max_casts` spells per turn and the
candidate action can never loop (the per-turn counter is incremented independently
of cost). Pass `free=true` in a hand-written `[candidate_action]` to cast for free.
The selection is stateless (run in both eval and exec), so multiple casting CAs on
one side never clobber each other. Register once per side, in or after `prestart`.

Limitations: targeting heuristics are per-profile (or `nearest`/`weakest` in the
explicit form); AoE placement and the rose `bend_*` push/damage aren't modelled.
A targeted spell's **range is supplied by the profile/macro**, since TRSS radii
live in `spells.cfg`, not `table.lua`.

---

## Spell definition format (`table.lua`)

Each spell in `spell_data.skill_set` is a table:

```lua
{
    id          = "fireball",           -- unique string, matches event name in spells.cfg
    label       = _"Fireball",          -- shown in buttons and menu
    image       = "spells/fireball.png",
    description = _"Burns enemies in a large area.",

    -- Optional costs (all nil = no cost, free to cast):
    xp_cost   = 20,    -- deducted from unit.experience
    hp_cost   = 5,     -- deducted from unit.hitpoints
    gold_cost = 3,     -- deducted from side gold
    atk_cost  = 1,     -- deducted from unit.attacks_left

    -- Optional subskills (shown as small buttons under the main spell in cast mode):
    subskills = {
        { id="fireball_small", label=_"Small", image="...", xp_cost=10, description="..." },
    },
}
```

`spell_data.locked` is a sentinel entry (id `"skill_locked"`) shown for spells not yet unlocked.

---

## How to add a new caster

1. Add an `[assign_caster]` block in the scenario `[event name=prestart]`:

```cfg
[assign_caster]
    [filter] id=MyHero [/filter]
    spell_group_1 = "heal,greater_heal"
    spell_group_2 = "shield,greater_shield"
    unlocked_spells = "heal,shield"
    equipped_spells = "heal,shield"
[/assign_caster]
```

2. Define the spell events in `spells.cfg` (or a scenario-local file) triggered by `refresh_skills`:

```cfg
[event]
    name=refresh_skills
    first_time_only=no
    {CHECK_EQUIPPED_SPELL (id=$current_caster) heal}
    [if]
        [variable] name=equipped_spell_found op=equals value=true [/variable]
        [then]
            [object]
                duration=forever
                silent=yes
                [filter] id=$current_caster [/filter]
                [effect] apply_to=ability [ability]...[/ability] [/effect]
            [/object]
        [/then]
    [/if]
[/event]
```

3. Define the cast event (fired when the player clicks the spell button):

```cfg
[event]
    name=heal
    first_time_only=no
    [lua] code= << ... >> [/lua]
[/event]
```

---

## How to add a new spell

1. Add its definition to `table.lua` inside `skill_set = { ... }`.
2. Add it to the relevant caster's `spell_group_N` in `[assign_caster]`.
3. Add a `[event name=refresh_skills]` block in `spells.cfg` to apply its ability when equipped.
4. Add a `[event name=<spell_id>]` block for the cast effect.

---

## Upgrade: Free Reselect

Unlocked per-caster via `[caster_reselect] reselect_allowed=yes`.

When active, a "Change Spells" button appears at the bottom of the **cast dialog** (above Cancel). Clicking it closes the dialog and immediately reopens it in **selection mode**, letting the player change their equipped spells mid-scenario. After confirming (or postponing), the cast dialog can be reopened normally.

This is purely a UI flow change — no game-state is modified beyond what the normal selection dialog already does.

---

## Upgrade: Multi-Cast

Unlocked per-caster via `[caster_max_casts] max_casts=N`.

When `max_casts > 1`, the bottom of the **cast dialog** shows a colored counter: `X/N casts remaining`. Spell buttons are blocked only when `casts_this_turn >= max_casts`. The counter resets to 0 at `turn refresh` / `start`.

The counter is incremented via the `spellcasting_cost` synced command (flag `casts_increment=true`), so it is properly reflected in savegames and replays on all clients.

Setting `max_casts=1` (or calling `[caster_max_casts] max_casts=1`) restores default behavior and hides the counter.

---

## Upgrade: Free Assign

Unlocked per-caster via `[caster_free_assign] free_assign_allowed=yes`.

When active, the **selection dialog** replaces the per-group menu buttons with one
clickable slot per group. Clicking a slot (its image or its name) opens a **spell
picker**: a grid of every spell in the catalogue, each cell showing the spell's
image and name. Hovering a cell shows a tooltip with the spell's description and
cost; clicking a cell closes the picker and assigns that spell to the slot.

The picker is a nested, purely-local dialog (no game state changes) opened from
within the selection dialog's `evaluate_single` block; the chosen id is stored in
the slot through a Lua table. Only **Confirm** commits the result: the per-slot spell
ids are written to WML variables in the button handler, read back after the dialog,
and applied via `[magic_apply_selection]` (see *Committing a selection* under
Multiplayer model). Because the caster is in free-assign mode, that action calls
`assign_free`, which rebuilds the caster's groups (one spell each), unlocks every
chosen spell, and rewrites the equipped list, then fires `refresh_skills`. Because
the result still flows through `groups` / `equipped` / `unlocked`, **cast mode and
`spells.cfg` need no changes**. "Choose Later" only sets the `wait_to_select_spells`
flag.

Slot count is normally the caster's number of `spell_group_N` entries, but if those
are missing (a caster whose state was reset), it falls back to
`max(max_casts, #equipped, 3)` empty slots so free-assign always works and can
rebuild a caster from nothing. Empty slots are tracked with `false` (never `nil`) so
the slot array length stays correct.

Confirm stays disabled until every slot holds a spell. Slot count equals the
caster's number of `spell_group_N` entries. Setting `free_assign_allowed=no`
restores the default per-group menu selection UI.

To prevent duplicates, the picker disables any spell already chosen in another
slot (the slot's own current spell stays selectable). The disabled set is rebuilt
from the other slots' choices each time the picker opens.

---

## Upgrade: Free Pick (unlocked-only)

Unlocked per-caster via `[caster_free_unlocked] free_unlocked_allowed=yes`.

Free-pick reuses the entire free-assign UI and commit path — one clickable slot
per group, a picker grid, confirm-disabled-until-full, no-duplicate handling, and
`assign_free` on commit. The **only** difference is the picker's contents: instead
of `all_spells_sorted()` over the whole catalogue, the grid is filtered to the
caster's `unlocked_set` via `open_picker`'s `allowed_set` argument.

To keep state consistent, any slot that opens pre-filled with a now-locked spell is
cleared to empty (`false`), so a locked spell can never be confirmed through
free-pick. If a caster has both `free_assign` and `free_unlocked`, `free_assign`
takes precedence (the full catalogue), since it is the strict superset.

This is the lightest-weight way to give a caster "free choice, but only from what
they've earned": no new dialog, no new commit logic, just a filtered picker.

## File map

| File | Role |
|---|---|
| `magic/utils.cfg` | Entry point. Includes other cfg files, loads `core.lua`, defines global events (turn reset, anti-leveling, etc.) |
| `magic/macros.cfg` | WML macros for use in scenario files |
| `magic/spells.cfg` | `refresh_skills` event handlers that apply/remove unit abilities; individual spell cast events |
| `magic/TRSS.cfg` | Adjacent spell targeting system (separate from main magic flow) |
| `magic/core.lua` | All `wml_actions`, caster registry, double-click handler |
| `magic/state.lua` | WML ↔ Lua data bridge (`load` / `save` / `delete` / `from_config`) |
| `magic/ops.lua` | Pure functions on caster data tables |
| `magic/dialog.lua` | Dialog layout, preshow wiring, evaluate_single orchestration |
| `magic/ai.lua` | Adaptive AI casting engine: candidate-action eval/exec, per-kind valuation |
| `magic/ai_profiles.lua` | Editable catalogue of how the AI uses each spell (add/remove a line) |
| `magic/table.lua` | Read-only catalogue of all 36 spell definitions |
