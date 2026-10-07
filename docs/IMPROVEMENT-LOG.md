# Improvement run log

Append-only record for the [improvement plan](IMPROVEMENT-PLAN.md). Add the
newest entry at the bottom. Never edit an old entry; correct it with a new one.

## Entry template

```text
### YYYY-MM-DD task <id>: <title>
Result: done | reverted | skipped | rejected | blocked
Pins: SunPad <sha>, ModernGekko <sha>, RecompCore <sha>, DolRecomp <sha>
Checkpoints: C1 pass/fail (detail); C2 <baseline> -> <candidate>, noise <x>%;
  C3 <device, route, median/worst speedRatio before -> after>; C4 <sizes, times>;
  C5 <who, scenes, verdict>
Evidence: <log or artifact paths outside Git, PR links>
Notes: <what was learned; why kept, reverted or stopped>
Next: <the next task or the question for a human>
```

## Measurements

Record each pin set's noise floor and the pass 2 ranking table here when they
exist.

## Ideas

Unmeasured ideas. Promote one to a task card only through the plan's
[candidate intake](IMPROVEMENT-PLAN.md#adding-new-work).

- Metal binary archives for known pipelines (from the performance research).
- Hot-region LLVM objects for measured chunks (from the performance research).

## Entries

### 2026-10-07 plan: created
Result: done
Pins: SunPad c77dd61, ModernGekko 8f49c55, RecompCore da96175, DolRecomp fa0cf61
Checkpoints: documentation only
Evidence: [sms-pc-port review](SMS-PC-PORT-REVIEW.md)
Notes: Symbol map hash matches the extracted main.dol. The pinned DolRecomp
  already inlines the FP-enabled check and has an opt-in direct-call path that
  is off. ModernGekko supports code mods, but SunPad does not set
  mod_directories. Dolphin's GCI folder writes saves in place.
Next: task 1.1 and task 2.1 (independent).

### 2026-10-07 plan: agent entry points
Result: done
Pins: unchanged
Checkpoints: documentation only
Evidence: AGENTS.md, CLAUDE.md, plan "Start here" section
Notes: AGENTS.md now points agents to the plan; CLAUDE.md imports AGENTS.md so
  Claude-based agents get the same instructions. The status table marks what
  each task needs (source only, disc image, or a human). Releases stay paused.
Next: task 1.1 and task 2.1 (independent).
