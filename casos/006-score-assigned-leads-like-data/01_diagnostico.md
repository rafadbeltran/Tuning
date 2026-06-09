# Diagnóstico

## EXPLAIN ANALYZE da consulta original

```
-> Group aggregate: count(avel.score_assigned_leads.deal_id)  (cost=38777 rows=600) (actual time=98.7..621 rows=65 loops=1)
    -> Filter: (avel.score_assigned_leads.updated_time like '2026-06-05%')  (cost=34927 rows=38493) (actual time=44.1..621 rows=141 loops=1)
        -> Index scan on score_assigned_leads using FK_score  (cost=34927 rows=346471) (actual time=9.49..565 rows=359534 loops=1)
```

## Problema principal: `LIKE` em coluna de data/hora → não-sargável

`updated_time LIKE '2026-06-05%'` obriga o MySQL a **converter cada linha** de
`updated_time` (DATETIME/TIMESTAMP) para string antes de comparar o prefixo. Com isso
não há range de índice possível sobre a coluna — mesma família do caso
[001](../001-notifications-status-id/) (coerção de tipo travando o índice).

Resultado no plano: o acesso de base é um **`Index scan ... using FK_score`** que lê
**359.534 linhas** (a tabela inteira), e só depois o `Filter` do `LIKE` reduz para
**141**. Lê ~360 mil para reter 141 (**~0,04%** de seletividade) — daí os **~621 ms**.

## Por que ele escolheu o índice `FK_score`

`FK_score` é o índice da foreign key de `user_id`. O otimizador o varre inteiro **de
propósito**: as linhas saem já ordenadas por `user_id`, então o `GROUP BY user_id` é
resolvido em streaming (`Group aggregate`), sem temporary table nem sort. Ele trocou
"não pagar o sort do GROUP BY" por "ler a tabela toda" — porque, **sem índice em
`updated_time`, não existia a opção de range** que cortaria as linhas lá embaixo.

## Estimativa furada confirma a falta de índice

`Filter ... rows=38493` (estimado) vs. `rows=141` (real). O otimizador chuta ~11%
genérico para o `LIKE` por não ter estatística/índice útil sobre `updated_time`. Com um
índice de range na coluna, a estimativa passa a bater com o real.

## Pontos secundários

- **`COUNT(deal_id)` vs `COUNT(*)`**: `COUNT(deal_id)` ignora `deal_id` NULL. Se
  `deal_id` for `NOT NULL`, é equivalente a `COUNT(*)` — confirmar no `SHOW CREATE
  TABLE` (afeta se vale ou não incluir `deal_id` no índice covering).
- **Ordenação do GROUP BY**: ao trocar para um índice liderado por `updated_time`
  (ver tuning), as ~141 linhas do range deixam de vir ordenadas por `user_id`, então
  aparece um pequeno **filesort** para o GROUP BY. É irrelevante — ordenar 141 linhas
  é praticamente de graça perto de não ler as outras ~359 mil.

## Resultado após o tuning (range half-open + índice `idx_sal_updated_user_deal`)

`EXPLAIN ANALYZE` depois:

```
-> Table scan on <temporary>  (actual time=0.114..0.124 rows=65 loops=1)
    -> Aggregate using temporary table  (actual time=0.113..0.113 rows=65 loops=1)
        -> Filter: ((avel.score_assigned_leads.updated_time >= TIMESTAMP'2026-06-05 00:00:00') and (avel.score_assigned_leads.updated_time < TIMESTAMP'2026-06-06 00:00:00'))  (cost=29.5 rows=141) (actual time=0.0305..0.069 rows=141 loops=1)
            -> Covering index range scan on score_assigned_leads using idx_sal_updated_user_deal over ('2026-06-05 00:00:00' <= updated_time < '2026-06-06 00:00:00')  (cost=29.5 rows=141) (actual time=0.0287..0.0529 rows=141 loops=1)
```

| Métrica           | Antes                              | Depois                                         |
|-------------------|------------------------------------|------------------------------------------------|
| Acesso à tabela   | `Index scan using FK_score`, ~359.534 linhas | `Covering index range scan`, 141 linhas |
| Linhas lidas      | 359.534 para reter 141             | 141 (lê só o que precisa)                      |
| Estimativa × real | `rows=38493` vs `141` (furada)     | `rows=141` vs `141` (bate)                     |
| Tempo             | ~621 ms                            | ~0,12 ms                                       |

Os ganhos previstos apareceram:

1. **Range scan covering** em `idx_sal_updated_user_deal` lendo só as 141 linhas do dia
   — não toca mais na tabela nem varre o índice inteiro.
2. A estimativa do otimizador passou a **bater com o real** (sinal de que agora há
   índice/estatística útil sobre `updated_time`).
3. **~621 ms → ~0,12 ms** (~5000×). O ganho vem de **deixar de ler ~359 mil linhas**,
   então vale igual a frio (não depende de buffer pool).

O `Aggregate using temporary table` que sobrou é o custinho previsto do `GROUP BY`
(liderança do índice é `updated_time`, não `user_id`): materializa 65 grupos sobre 141
linhas em ~0,01 ms. Não compensa um segundo índice liderado por `user_id` só para
removê-lo.
