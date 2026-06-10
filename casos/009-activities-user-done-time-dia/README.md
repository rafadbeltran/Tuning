# 009 — `avel.activities` — atividades do dia por lista de usuários

**Status:** 🟢 Resolvido — índice composto `(user_id, done_time)` trocou o full scan de
4,46M por um index range scan de 317 linhas (42 ranges, um por usuário): **~8.857 ms →
~3,87 ms (~2.300×)**. Sem reescrever a consulta (já era sargável).

Atividades concluídas (`done_time`) num único dia, para uma lista de `user_id`,
`is_deleted = 0`, ordenadas por `done_time DESC`. Duas versões no baseline: lista de 42
users (A) e um único user_id (B) — mesma forma, o índice serve as duas.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline (versões A e B, formatadas).
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — índice proposto e validação (sem reescrita).
- [`03_procedure.sql`](03_procedure.sql) — consulta parametrizada (CSV de `user_id` + período) como stored procedure.

## Resumo do diagnóstico

A query é **sargável** (range em `done_time`, `IN` em `user_id`, igualdade em
`is_deleted`) mas **não tem índice** que a atenda → **full table scan de ~4,46M linhas**
para reter **317** (~0,007%), **~8,86 s a quente** (minutos a frio). O `Sort: done_time
DESC` não é o gargalo (ordena só 317 linhas; espera o scan). Fix = **criar o índice,
sem reescrever a consulta**.

## Ordem de ataque

1. Índice composto **`(user_id, done_time)`** — com `IN`, vira N range scans por
   usuário já na ordem de `done_time` (~317 linhas em vez de 4,46M). Resolve A e B.

## Pendências

- [x] Criar o índice, re-rodar `EXPLAIN ANALYZE` e colar o "depois" (8.857 ms → 3,87 ms).
- [x] `metricas_casos.csv` preenchido.
- [ ] `SHOW CREATE TABLE avel.activities` — confirmar que não ficou índice redundante por `user_id`.
- [ ] Medir a frio (atualizar `tempo_antes` se adotar o critério frio→frio).
- [ ] (Opcional) incluir `is_deleted` no índice só se houver muitos deletados.
