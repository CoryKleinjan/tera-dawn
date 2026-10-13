# Jobs

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a job

Create `data/jobs/<id>.tres` as a **JobDef**: primary and secondary stat, mastery, HP and MP
growth, Ability Points per level, its `family` (the job line gear names in `EquipDef.jobs`),
and a `tint` the hero is drawn in until the job has its own art.

Everyone starts as `Character.START_JOB` (the Beginner, which lists starting stats, gear,
items and the potions put on the last quickslots, `starting_quickslots`). A job that others
reach sets `advances_from`, `advance_level`, `advance_requirements`
(base STR/DEX/INT/LUK) and `advance_gifts`: the job's basic shop weapon (the first weapon
listed is worn at once in place of a Beginner's weapon; one of the job's own line stays on),
and potions. Better weapons only drop. To let an NPC hand it out, add its id to that
NPC's `instructs`: their dialogue then offers "Choose a job", and the server
(`ServerJobs.on_advance` → `Character.advance`) checks the requirements again before changing it.
`advance_quest` is a quest to hand in first, the tutor's Job Test (`data/quests/jtest_<job>.tres`:
beat the tear boss on the town's Trial Ground, see [maps](maps.md)); handing it in advances you
at once (`ServerQuests.on_quest_complete`), and the other four jobs then report to Celest
(`jreport_<job>`, started by itself).
A Beginner short of a job's stats may also ask its instructor for one free Ability Point reset
per character (`req_reset_ap` → `AbilityPoints.reset`): base stats go back to the job's
`starting_stats` and the points come back. `AbilityPoints.reset_used` is saved with the rest.
