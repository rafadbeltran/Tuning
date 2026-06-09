# 008 — `intranet.customer` — won/lost por lista de assessores na janela do mês

**Status:** ⚪ Backlog

Deals ganhos/perdidos por ~54 assessores (`won_by_id`/`lost_by_id`) dentro de
junho/2026, `status IN ('won','lost')`. Projeção com ~60 colunas.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.

## Suspeita (a confirmar com EXPLAIN)

- **`OR` entre duas colunas diferentes** (`won_by_id ... OR lost_by_id ...`) +
  **`OR` entre duas janelas de data** (`won_date` / `lost_date`) → o otimizador
  geralmente desiste do índice e cai em **full scan** (ou table scan + filtro).
- Padrão clássico para **reescrita com `UNION ALL`**: um ramo "ganhos"
  (`won_by_id IN (...) AND won_date BETWEEN ... AND status='won'`) e outro "perdidos"
  (`lost_by_id ... AND lost_date ... AND status='lost'`), cada ramo cravando um
  índice composto.
- Índices candidatos: `(won_by_id, won_date)` e `(lost_by_id, lost_date)` (status é
  derivável/redundante, confirmar).
- Projeção de ~60 colunas: confirmar se todas são usadas (impacto de I/O, não o
  gargalo principal).

## Pendências

- [ ] `EXPLAIN` do baseline (esperado full scan por causa dos `OR`).
- [ ] Protótipo `UNION ALL` + índices compostos; comparar tempo.
- [ ] Conferir cardinalidade da janela (quantas linhas no mês).
