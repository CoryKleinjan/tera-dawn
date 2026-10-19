# Jobs

Part of the [architecture docs](../../ARCHITECTURE.md).

## How to add a job

Create `data/jobs/<id>.tres` as a **JobDef**: its `family` (the job line gear names in
`EquipDef.jobs`) and its `description`. A job adds no stats: damage comes from the weapon (see
[items](items.md)).

Everyone starts as `Character.START_JOB` (the Beginner, which lists starting gear,
items and the items put on the last quickslots, `starting_quickslots`). A job that others
reach sets `advances_from` and `advance_gifts` (gear comes from vendors and secrets, never
drops). To let an NPC hand it out, add its id to that
NPC's `instructs`: their dialogue then offers "Choose a job", and the server
(`ServerJobs.on_advance` → `Character.advance`) checks again before changing it
(`Character.can_become`: a first job to anyone past the Beginner, a blend to its parents, any
job passed before).
`advance_quest` is a quest to hand in first, the tutor's Job Test (`data/quests/jtest_<job>.tres`:
beat the tear boss on the town's Trial Ground, see [maps](maps.md)); handing it in advances you
at once (`ServerQuests.on_quest_complete`), and the other four jobs then report to Celest
(`jreport_<job>`, started by itself).
The jobs passed are saved (`Character.jobs_passed`), so switching back needs no Job Test and gives no gifts again.

## How to add a blend (second tier)

A blend is a JobDef with `advances_from` and `partner` set to its two first jobs. Either parent can advance into it
(`JobDef.opens_from`); the character remembers which (`Character.came_from`, saved), and
`Character.job_path` runs back through that one. It wears either parent's gear
(`JobDef.wear_families`). No tutor offers the blends yet: a later tutor will, by listing
their ids in its `instructs`. The first-job instructors never offer them.

