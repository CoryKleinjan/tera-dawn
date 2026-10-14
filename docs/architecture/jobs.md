# Jobs

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a job

Create `data/jobs/<id>.tres` as a **JobDef**: its one main stat (`primary_stat`), mastery, HP and MP
growth, Ability Points per level, its `family` (the job line gear names in `EquipDef.jobs`),
and a `tint` (the job's colour, where jobs are shown).

Everyone starts as `Character.START_JOB` (the Beginner, which lists starting stats, gear,
items and the potions put on the last quickslots, `starting_quickslots`). A job that others
reach sets `advances_from`, `advance_level`, `advance_requirements`
(base STR/DEX/INT/LUK/CHA, usually just the main stat) and `advance_gifts`: potions for now;
once gear returns, also the job's basic shop weapon and off-hand (the first of each is worn at
once in place of a Beginner's; one of the job's own line stays on). Better weapons only drop. To let an NPC hand it out, add its id to that
NPC's `instructs`: their dialogue then offers "Choose a job", and the server
(`ServerJobs.on_advance` → `Character.advance`) checks the requirements again before changing it.
`advance_quest` is a quest to hand in first, the tutor's Job Test (`data/quests/jtest_<job>.tres`:
beat the tear boss on the town's Trial Ground, see [maps](maps.md)); handing it in advances you
at once (`ServerQuests.on_quest_complete`), and the other four jobs then report to Celest
(`jreport_<job>`, started by itself).
A Beginner short of a job's stats may also ask its instructor for one free Ability Point reset
per character (`req_reset_ap` → `AbilityPoints.reset`): base stats go back to the job's
`starting_stats` and the points come back. `AbilityPoints.reset_used` is saved with the rest.

## How to add a blend (second tier)

A blend is a JobDef with `advances_from` and `partner` set to its two first jobs and
`secondary_stat` set to the partner's stat. Either parent can advance into it
(`JobDef.opens_from`); the character remembers which (`Character.came_from`, saved), and
`Character.job_path` runs back through that one. `Character.job_line` adds the other parent,
so its skill book opens too (the skill window shows its tab just before the blend's).
Damage adds both stats together (`JobDef.damage_stat_value`, and Magic Attack for a blend with
INT); Auto splits points evenly (`AbilityPoints.auto_plan`); it wears either parent's gear
(`JobDef.wear_families`). No tutor offers the blends yet: a later tutor will, by listing
their ids in its `instructs`. The first-job instructors never offer them.

