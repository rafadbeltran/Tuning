# 006 — `score_assigned_leads` — `updated_time LIKE '2026-06-05%'`

**Status:** 🟢 Resolvido — range half-open + índice covering
`(updated_time, user_id, deal_id)` trocou o index scan de ~359.534 linhas por um
covering range scan de 141 linhas; **~621 ms → ~0,12 ms** (~5000×).

Contagem de leads por `user_id` num dia, filtrando `updated_time` com `LIKE` de
prefixo de data.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — reescrita sargável + índice, em ordem de aplicação.

## Resumo do diagnóstico

`updated_time LIKE '2026-06-05%'` não é sargável (converte a coluna para string por
linha). O plano faz `Index scan using FK_score` lendo **359.534 linhas** (a tabela
toda) para reter **141** — daí os **~621 ms**. O índice `FK_score` (FK de `user_id`)
foi escolhido só porque entrega a ordem do `GROUP BY` de graça; não havia índice de
range em `updated_time`.

## Ordem de ataque

1. Reescrever o `LIKE` como **range half-open** `>= '2026-06-05' AND < '2026-06-06'`.
2. Índice covering **`(updated_time, user_id, deal_id)`** — range corta para ~141
   linhas e cobre a consulta (pequeno filesort do GROUP BY é desprezível).

## Pendências

- [x] Aplicar o índice, re-rodar o `EXPLAIN ANALYZE` e colar o plano "depois"
      (ver [01_diagnostico.md](01_diagnostico.md)).
- [x] Preencher a linha no `metricas_casos.csv` (621 ms → 0,12 ms).
- [ ] Conferir se `deal_id` é `NOT NULL` — se for, dá para usar `COUNT(*)` e enxugar o
      índice para `(updated_time, user_id)` (melhoria opcional, não bloqueia).
