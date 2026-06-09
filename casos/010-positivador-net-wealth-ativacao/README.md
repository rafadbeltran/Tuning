# 010 — `avel.positivador` — net por cliente + último wealth + última ativação

**Status:** ⚪ Backlog

Para um assessor (`user_id = 1591`), somar o `net_em_m` por `customer_id`, anexar o
`wealth_range` mais recente e a última data de ativação. Usa CTEs com `ROW_NUMBER` e
`MAX`.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline **(TRUNCADO** —
  termina no `LEFT JOIN avel.customers`; completar).

## Suspeita (a confirmar com EXPLAIN)

- `w_latest` usa `ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY date DESC)`
  sobre a tabela **inteira** de `customer_wealth_range_in_month` — se não houver
  índice `(customer_id, date)`, é window sort caro. Avaliar materializar só os
  customers do `p_agg`.
- `ar_latest` agrega `bi.activation_records` inteira por `client` — checar índice
  `(client, date)` / filtro `activation = 1`.
- `p_agg` filtra `user_id = 1591` e `customer_id IS NOT NULL` — índice
  `(user_id, customer_id)` em `positivador`.
- Há `MAX(ar.date)` no SELECT externo sem `GROUP BY` visível (parte truncada) —
  confirmar agregação ao completar.

## Pendências

- [ ] **Completar a query** (faltam JOINs com `w_latest`/`ar_latest` e `GROUP BY`).
- [ ] `EXPLAIN` e índices das 3 tabelas.
