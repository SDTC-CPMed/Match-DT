# Agent notes — Match-DT

For environment setup, EHR profiling, column maps, ICD-10 JSON mapping with human confirmation, trajectory runs, and verification, follow:

**[`skills/match-dt-trajectories/SKILL.md`](skills/match-dt-trajectories/SKILL.md)**

That skill is agent-agnostic. A symlink at `.cursor/skills/match-dt-trajectories` exists only for Cursor discovery; other agents should load `skills/match-dt-trajectories/` directly.

Do not read `tests/fixtures/dummy_dirty_solution/` unless the user asks to grade a dirty-data run.
