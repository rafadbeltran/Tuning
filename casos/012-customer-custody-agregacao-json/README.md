# 012 — Custódia do cliente — agregação JSON gigante

**Status:** ⚪ Backlog

Monta o "perfil de custódia" por cliente: soma de net, `GROUP_CONCAT` de códigos/deals
e dezenas de `JSON_OBJECT`/`JSON_EXTRACT` (renda fixa/variável, seguros, internacional,
consórcio, mesa trader, previdência...), juntando ~7 tabelas (aliases `a`..`h`).

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline **(TRUNCADO** — para
  no meio do `JSON_OBJECT` de previdência; faltam os `FROM`/JOINs, `WHERE` e
  `GROUP BY`; completar).

## Suspeita (a confirmar com EXPLAIN)

- Query "kitchen-sink": muitos joins + agregação pesada + `GROUP_CONCAT` + muitos
  `MAX(JSON_EXTRACT(...))` por grupo. Custo provável vem dos **joins/varreduras** e da
  materialização do grupo, não do JSON em si — confirmar com EXPLAIN antes de otimizar.
- Riscos a checar: `GROUP_CONCAT` estourando `group_concat_max_len` (truncamento
  silencioso do JSON montado à mão via `CONCAT('[',...,']')`); `CAST(... AS JSON)` sobre
  string truncada quebra.
- Avaliar índices nas chaves de join e se dá para **pré-agregar** subconjuntos (ex.: o
  bloco `h.*` de JSON) antes do join.

## Pendências

- [ ] **Completar a query** (JSON_OBJECTs finais + `FROM`/JOINs/`WHERE`/`GROUP BY`).
- [ ] Mapear as 7 tabelas (`a`..`h`) e suas chaves de join.
- [ ] `EXPLAIN` para achar o gargalo real antes de mexer.
