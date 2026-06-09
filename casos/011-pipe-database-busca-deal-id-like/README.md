# 011 — `pipe_database` — busca de `deal_id` com `CAST(... AS CHAR) LIKE '%n%'`

**Status:** ⚪ Backlog

Busca tipo "autocomplete" por `deal_id`: traz quem *contém* o número digitado e
prioriza o match exato no `ORDER BY`. `LIMIT 10`.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.

## Suspeita (a confirmar com EXPLAIN)

- **Dois problemas de sargabilidade somados:**
  1. `CAST(deal_id AS CHAR)` — converte a coluna a cada linha → índice em `deal_id`
     fica inutilizável (mesma família do caso [001](../001-notifications-status-id/)).
  2. `LIKE '%...%'` com **curinga à esquerda** → mesmo sobre texto, não há range de
     índice possível. Resultado: **full scan** + filtro + filesort do `ORDER BY CASE`.
- Caminhos a avaliar:
  - Se a intenção é "começa com" e não "contém", trocar por `LIKE '3091%'` sobre uma
    coluna textual indexada → vira range scan.
  - Se "contém" é requisito de produto, considerar coluna textual gerada +
    índice/FULLTEXT, ou empurrar a busca para um motor próprio (search).
  - Se o uso real é buscar **o** deal (match exato/prefixo numérico), comparar
    `deal_id` numericamente em vez de string.

## Pendências

- [ ] Confirmar o tipo de `deal_id` e a intenção da busca (contém vs. começa-com vs. exato).
- [ ] `EXPLAIN` do baseline e proposta conforme a intenção.
