# A45b full-result arbitration and server-search correction — 2026-10-03

- `5606de0` (worker `6ca66c1`) stamps each actual page/individual dispatch. A full exact-topic row is rejected only after a
  higher ordinal has committed; a newer pending/failed request does not discard usable older data. Shared admission preserves
  post-dispatch scalar/info changes and records accepted removal ordinals. Raw TD cursors remain independent of filtered rows.
  Full-response comparison baselines use captured read revision, not global completion revision: an unrelated topic update
  cannot turn an older full response into a newer live event. Independent review caught that draft seam before integration.
- Native PID45056 on 5606de0 PASS: all A45a cases plus both completion orders, older-data visibility while newer read waits,
  newer failure, unrelated-topic events, later hide/rename removal, raw cursor, and a fresh later response replacing an old
  tombstone. This is a local full-response precedence policy, not proof of server causal ordering or originating RPC IDs in updates.
- Primary found a missed regression after initial review: new page filtering reused the legacy individual `contains` matcher.
  Actual PID50531 on 5606de0, literal Geberal query, showed No topics found; prior 80b070b PID36808 returned General for that
  typo. The pinned getForumTopics API supplies server-filtered results and does not promise substring matching. Screenshot
  `b1-search-geberal.png` confirms failure; `b1-search-failure.png` is an earlier literal-General success despite its filename.
- `16cf99e` (worker `06159e6`) preserves raw server-page membership. Only a genuinely newer different name may invalidate
  that result locally; unchanged/same-name info echoes do not. Hidden topics remain excluded. Controlled cases cover fuzzy
  results, pending-page same-name echoes, later rename/hide and raw cursor.
- Correction native PID61547 PASS all A45a/b cases and server-query membership cases. Actual PID64127 on 16cf99e: same
  literal Geberal query returns General/topic1 at x0/y62/w402/h61.3333. Before/after screenshots b1-search-geberal and
  b2-search-geberal were inspected; Cancel restores all six topic IDs. This closes the introduced page-filter regression
  for this real query, not every server search behavior or later info/individual-refresh lifetime. No topics opened or writes sent.
- Builds: primary053808-44178-22355 PASS23s, correction054358-59116-5045 PASS8s; worker053416-40099-30375 PASS11s,
  correction054200-53359-6587 PASS10s. Each two-file Swift delta formatted together; full logs zero warnings/errors and
  immutable review passed. The original review missed server-versus-local search semantics; the runtime failure is preserved.
- Follow-up identified as A45c: legacy info observer and individual refresh still apply contains to a known server-matched row, so same-name
  notifications can remove fuzzy results. Preserve only exact query/topic/name membership already granted by a current page;
  unknown lookups must not gain invented fuzzy authority. A bounded extra unknown refresh after page omission is also recorded;
  it is not the former unbounded echo loop. A46 pin ordering remains separate.
