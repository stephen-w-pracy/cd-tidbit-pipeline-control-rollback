# Parity Matrix

CLAUDE.md requires the README, pipeline YAML, narrator script, and specs to stay
in parity. This is the **exact mapping** of what tracks with what, so a change in
one place tells you precisely which other places to update.

> Referenced from `CLAUDE.md`. When you edit any row, check every cell in that row.

---

## 1. The four controls → where each is defined and demonstrated

| Control | Source of truth (`.harness/`) | README | `video/script.md` act | `video/production-spec.md` act | `specs/build.md` |
|---|---|---|---|---|---|
| **Input Sets** | `inputsets/dev-only.yaml`, `inputsets/full-release.yaml` (`target_envs`) | "Run the Demo" Steps 1–2; controls table | Act 2 | Act 2 | §Pipeline Controls |
| **Execution-time variables** | `pipeline.yaml` (`<+"v"+pipeline.sequenceId>`); `k8s/Dev.yaml`/`Prod.yaml` (`<+artifact.version>`, `<+artifact.image>`) | "Version label" note; controls table | Act 3 | Act 3 | §Pipeline Variables |
| **Conditional execution** | `pipeline.yaml` Deploy_to_Prod `when.condition` | Step 1 (Prod skipped) / Step 2 (Prod runs); controls table | Act 2 | Act 2 | §Pipeline Controls |
| **Post-prod rollback** | `pipeline.yaml` `rollbackSteps` (`K8sRollingRollback`) | Step 4; "What a Post-Prod Rollback Actually Is" | Act 5 (+ Brief Aside) | Act 5 (+ Brief Aside) | §Rollback behavior |

The lifecycle order (CLAUDE.md framing) is **Input Sets → execution-time
variables → conditional execution → post-prod rollback** — the order they appear
in the demo, not the order analyzed through rollback.

---

## 2. Golden-path runs → narrative beats

The demo is four pipeline runs. Every doc must describe the *same* four runs in
the same order. Version numbers are illustrative (`v1`/`v2`/`v3`); the real
numbers depend on prior runs.

| Run | Input set | Result | README | `video/script.md` | `video/production-spec.md` |
|---|---|---|---|---|---|
| 1. Dev only | Dev Only (`target_envs=dev`) | v1 → Dev; **Prod skipped** | Step 1 | Act 2 | Act 2 |
| 2. Full release | Full Release (`dev,prod`) | v2 → Dev **and** Prod | Step 2 | Act 3 | Act 3 |
| 3. Full release again | Full Release (`dev,prod`) | v3 → Dev and Prod (creates rollback history) | Step 3 | Act 4 | Act 4 |
| 4. Rollback | — (separate execution) | Prod reverts v3 → v2; Dev stays v3 | Steps 4–5 | Act 5 | Act 5 |

**Invariant:** rollback needs **≥2 successful Prod deploys** (runs 2 and 3)
before run 4 is possible. Every doc that mentions rollback must preserve this.

---

## 3. Document roles (don't duplicate across these)

| Doc | Role | Contains | Does **not** contain |
|---|---|---|---|
| `README.md` | Learner-facing runbook | Setup steps, golden-path run instructions, troubleshooting | Narration, shot lists, design rationale |
| `video/script.md` | Narrator script | Spoken words (blockquotes) + bracketed on-screen actions, by act | Shot framing, camera notes |
| `video/production-spec.md` | Production spec | Act structure, shot lists, key callouts, production notes | Spoken narration (lives in `script.md`) |
| `specs/build.md` | Design spec | Skill interpretation, objectives, decisions, controls/variables/resources tables | Step-by-step learner instructions |
| `docs/resource-map.md` | Identifier graph + templating layers | Who references whom; `${}`/`<+>`/`{{}}` ownership | Demo narrative |
| `docs/placeholders.md` | `${VAR}` → `.env` → consumers | Placeholder table, render verification | — |

---

## 4. Change-impact checklist

When you change… | …re-check these
---|---
`pipeline.yaml` stage/variable names or `when` condition | README controls table + "Run the Demo"; `video/script.md` acts; `video/production-spec.md` callouts; `specs/build.md` tables; `docs/resource-map.md` §2
An input set (`target_envs`, env/infra refs) | README Steps 1–2; both `video/script.md` & `video/production-spec.md` Act 2; `docs/resource-map.md` §2
A resource identifier (rename) | `docs/resource-map.md` §1–2; every cross-referencing `.harness/` file; `scripts/setup.sh` (endpoint IDs)
A `${VAR}` placeholder (add/remove/rename) | `docs/placeholders.md`; `.env.example`; `scripts/setup.sh` (`ENVSUBST_VARS`); the consuming `.harness/` file
Golden-path version numbers or run order | README "Run the Demo"; `video/script.md` Acts 2–5; `video/production-spec.md` Acts 2–5; §2 above
Screenshots in `readme-assets/` | README image refs; `video/production-spec.md` shot lists (if they cite the same frames)
The four-controls framing | `specs/build.md` "Skill Statement and Interpretation"; CLAUDE.md conventions; README "What You Will Learn"; §1 above
