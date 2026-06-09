# 009 — `avel.activities` — atividades do dia por lista de usuários

**Status:** ⚪ Backlog

Atividades concluídas (`done_time`) num único dia, para uma lista de `user_id`,
`is_deleted = 0`, ordenadas por `done_time DESC`. Duas versões: lista de ~42 users e
um único user_id.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline (2 versões).

## Suspeita (a confirmar com EXPLAIN)

- Filtro = `user_id IN (...)` + range de `done_time` no dia + `is_deleted = 0`, com
  `ORDER BY done_time DESC`. Sem índice composto adequado → provável **filesort** e/ou
  varredura maior que o necessário.
- Índice candidato: **`(user_id, done_time)`** (com `IN`, vira N range scans, um por
  user, já na ordem de `done_time`). Avaliar incluir `is_deleted` para cobrir o filtro.
- A ordenação global `done_time DESC` cruza vários `user_id`: com `IN` o MySQL pode
  precisar de merge/sort mesmo com o índice — medir filesort vs. sem.

## Pendências

- [ ] `EXPLAIN` (olhar `Using filesort` / `type` / `rows`).
- [ ] Testar `(user_id, done_time)` e variações; medir os dois cenários (42 vs 1 user).
