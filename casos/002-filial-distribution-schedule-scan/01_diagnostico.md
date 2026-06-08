# Diagnóstico

## EXPLAIN ANALYZE da consulta original

```
-> Table scan on <temporary>  (cost=165468..167340 rows=149530) (actual time=832..832 rows=8 loops=1)
    -> Temporary table with deduplication  (cost=165468..165468 rows=149530) (actual time=832..832 rows=8 loops=1)
        -> Filter: (schedule_id = 58387)  (cost=150515 rows=149530) (actual time=830..831 rows=1591 loops=1)
            -> Table scan on filial_distribution_positions  (cost=150515 rows=1.5e+6) (actual time=0.0259..752 rows=1.64e+6 loops=1)
```

## Problema principal: full table scan por falta de índice em `schedule_id`

A consulta lê **~1,64 milhão de linhas** (`Table scan ... rows=1.64e+6`, ~752 ms)
só para reter as **1.591** que batem com `schedule_id = 58387`. Não há índice em
`schedule_id`, então o otimizador não tem alternativa a varrer a tabela inteira.

Depois disso ainda monta uma **`Temporary table with deduplication`** para resolver
o `DISTINCT user_id` — trabalho extra que também sai de graça com o índice certo.

A estimativa do otimizador (`rows=149530`) está muito acima do real (`1591`), o que
confirma que ele não tem estatística/índice útil sobre `schedule_id`.

## Sintoma observado: 5 s a frio, ~832 ms a quente

- **1ª execução: ~5 s** — buffer pool frio, a tabela inteira veio do disco.
- **2ª execução (este EXPLAIN): ~832 ms** — as páginas já estavam no buffer pool.

Essa diferença é exatamente a assinatura de um full scan: o custo varia conforme a
tabela está ou não em memória. O índice ataca a **causa** (deixa de ler 1,64M linhas,
passa a ler ~1.591), então o ganho aparece **mesmo na execução fria** — não depende
de cache.

## Pontos secundários

- O `DISTINCT` em si não é o gargalo (dedup de 1.591 → 8 linhas é barato). Ele só
  pesa porque hoje roda **depois** de varrer a tabela toda. Com o índice composto,
  a ordenação por `user_id` vem de graça e a temporary table tende a sumir.
- Vale conferir a PK da tabela: no InnoDB todo índice secundário já carrega a PK nas
  folhas. Se `user_id` fizer parte da PK, um índice só em `(schedule_id)` já seria
  covering — ver nota em [`02_tuning.sql`](02_tuning.sql).

## Resultado após o tuning (índice `idx_fdp_schedule_user`)

Criar o índice composto `(schedule_id, user_id)` resolveu o caso por completo.

`EXPLAIN ANALYZE` depois do índice:

```
-> Group (no aggregates)  (cost=322 rows=1223) (actual time=0.149..0.823 rows=8 loops=1)
    -> Covering index lookup on filial_distribution_positions using idx_fdp_schedule_user (schedule_id=58387)  (cost=163 rows=1591) (actual time=0.025..0.753 rows=1591 loops=1)
```

| Métrica          | Antes                                   | Depois                                        |
|------------------|-----------------------------------------|-----------------------------------------------|
| Acesso à tabela  | full table scan, ~1,64M linhas          | covering index lookup, 1.591 linhas           |
| `DISTINCT`       | `Temporary table with deduplication`    | `Group (no aggregates)` (ordenação do índice) |
| Tempo (a quente) | ~832 ms                                 | ~0,82 ms                                       |

Os três ganhos previstos apareceram juntos:

1. **Covering index lookup** lendo só as 1.591 linhas do schedule — não toca mais na tabela.
2. A **temporary table sumiu**: o `DISTINCT` virou `Group (no aggregates)`, resolvido pela
   ordem do índice.
3. **~832 ms → ~0,82 ms** (~1000×). Como agora só 1.591 linhas são lidas, o problema dos
   ~5 s a frio também deixa de existir — não há mais full scan para pagar no disco.

A estimativa do otimizador (`rows=1591`) passou a bater com o real (1.591) — sinal de que
agora ele tem um índice/estatística útil sobre `schedule_id`.
