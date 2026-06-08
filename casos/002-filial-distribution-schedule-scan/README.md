# 002 — `SELECT DISTINCT user_id` por `schedule_id` (MySQL / InnoDB)

**Status:** 🟢 Resolvido — o índice composto `(schedule_id, user_id)` trocou o full
scan por covering index lookup (1,64M → 1.591 linhas), eliminou a temporary table do
`DISTINCT` e derrubou de ~832 ms para ~0,82 ms (a quente).

Tuning de uma consulta sobre `app.filial_distribution_positions` (~1,64 milhão de
linhas) que lista os usuários distintos de um schedule. Fazia full table scan por
falta de índice em `schedule_id`.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — índice proposto e validações.

## Resumo do diagnóstico

A consulta varre **~1,64 milhão de linhas** para reter apenas **1.591** (`schedule_id
= 58387`), porque não há índice em `schedule_id`. Depois ainda monta uma *temporary
table with deduplication* para o `DISTINCT`. Sintoma clássico de full scan: **~5 s a
frio** e **~832 ms a quente** (buffer pool), conforme a tabela já esteja ou não em
memória.

## Ordem de ataque

1. Criar o índice composto covering `(schedule_id, user_id)` — troca o full scan por
   range scan (~1.591 linhas) e resolve o `DISTINCT` pelo próprio índice.
2. Antes, conferir `SHOW CREATE TABLE` / `SHOW INDEX`: se já existe índice por
   `schedule_id`, estender; se `user_id` é parte da PK, `(schedule_id)` já basta.

## Pendências

- [x] Aplicar o índice e re-rodar o `EXPLAIN ANALYZE` (ver [01_diagnostico.md](01_diagnostico.md)).
- [ ] Conferir PK e índices existentes (`SHOW CREATE TABLE` / `SHOW INDEX`) para garantir
      que não ficou índice redundante por `schedule_id`.
