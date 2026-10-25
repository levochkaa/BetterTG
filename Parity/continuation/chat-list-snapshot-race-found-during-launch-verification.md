# Chat-list snapshot race found during launch verification — 2026-09-05

- Real startup exposed a UITableView dequeue assertion: membership reached the diffable snapshot
  before the separately queued provider cache, causing a fallback cell with the wrong reuse type.
- Each snapshot now populates its cache first; applies serialize and coalesce pending identifiers.
  Old row objects survive removal animations and are pruned only after completion. This also
  prevents scope/account metadata bursts from racing structural list updates.
- Validation: warning-free wrapper build `build-Debug-20260905-180601-39253-15148.log`;
  fixed launch PID 39691 remained running, main/custom/archive populated with expected visible
  order, and the repeated native-cache probe passed nine checks. Evidence is under
  `.build/ui-probe-evidence/parity-fixes-20260905/stage2/`.
