# A45c known server-query row lifetime — 2026-10-03

- `79213e0` (worker `d24a554`) retains a known row only when accepted query, topic ID and name still match. Same-name info
  changes and inbox/draft refreshes no longer discard a server fuzzy match. Individual dispatch captures that name and verifies
  it against both current and admitted response after existing source/generation/UUID/ordinal checks. No fuzzy algorithm or
  transferable membership cache is added; unknown IDs keep the conservative matcher. Rename/hide/name ABA revoke the exception.
  Restored accepted-query rows retain display membership only, not fresh server metadata or permissions.
- Native PID76193 on 79213e0 PASS all A45a/b/c cases: same-name changed closed state, inbox/draft reads and echoes, unknown
  same-name ID exclusion, rename/hide/query/source ABA, late replies and a rebuilt VM from the accepted display seed. The seed
  fixture uses the same captured client, not a real client epoch. Actual source-renewal/search smoke at earlier 7aa093a and
  fuzzy before/after 1b0d836 remain separately scoped; no live remote edit/counting claim is inferred from these controlled reads.
- Native PID76765 active-search/restoration regressions PASS on 79213e0. Fresh result files timestamp05:56:14/05:56:07 (+04)
  were checked, then preserved as final probe outputs. All A45 evidence is under `.build/ui-probe-evidence/astra-a45-topic-updates/`.
- Two changed Swift files formatted together; primary055412-75499-10026 PASS10s, worker055207-73770-18802 PASS22s,
  complete logs zero warnings/errors. Independent immutable review passed. Next P1 is A44b2; A46 remains the separate visible
  pinned-order gap. Unknown-topic page omission may still cause one redundant refresh, not recursive identical-echo fetching.
