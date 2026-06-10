# 008 — `intranet.customer` — won/lost por lista de assessores na janela do mês

**Status:** 🟡 Em andamento — diagnóstico fechado (full scan de 3,96M, ~9,8 s a quente);
índices + reescrita `UNION ALL` propostos. Falta confirmar a semântica do `OR` cruzado,
ver o `SHOW CREATE TABLE`, aplicar e medir.

Deals ganhos/perdidos por 56 assessores (`won_by_id`/`lost_by_id`) dentro de
junho/2026, `status IN ('won','lost')`. Projeção com 59 colunas.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline (formatado).
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — índices + reescrita `UNION ALL`, com verificação.
- [`03_procedure.sql`](03_procedure.sql) — versão fiel (4 ramos) como stored procedure
  parametrizada (CSV de assessores + período).

## Resumo do diagnóstico

`OR` cruzando colunas diferentes — `won_by_id IN (...) OR lost_by_id IN (...)` **e**
`won_date BETWEEN ... OR lost_date BETWEEN ...` — impede o uso de índice → **full table
scan de ~3,96M linhas** para reter **7.047** (~0,18%), **~9,8 s a quente** (a frio deve
ser minutos). Estimativa furada (`rows=102520` vs `7047`) confirma a falta de caminho.

## Ordem de ataque

1. Índices `(won_by_id, won_date)` e `(lost_by_id, lost_date)` — um por ramo.
2. Reescrita com **`UNION ALL`** (ramo won + ramo lost), mutuamente exclusivos por
   `status`, cada um cravando seu índice. Range de data half-open.

## ⚠️ A confirmar antes de fechar

- **Semântica do `OR` cruzado:** o original aceita combinações "trocadas" (ganhou por
  um assessor, casou pela data em que perdeu). O `UNION ALL` de 2 ramos só é
  equivalente se **não existirem** linhas com `won_date` E `lost_date` preenchidos
  (verificação no `02_tuning.sql`). Caso existam, usar a variante fiel de 4 ramos.

## Pendências

- [ ] `SHOW CREATE TABLE intranet.customer` — PK, índices, tipos de `*_by_id`, NULL das datas.
- [ ] Rodar a verificação do PASSO 0 (linhas com as duas datas) e decidir 2 vs 4 ramos.
- [ ] Aplicar índices + reescrita, re-rodar `EXPLAIN ANALYZE` e colar o "depois".
- [ ] Conferir que a contagem de linhas bate com o original.
- [ ] Medir a frio e preencher `metricas_casos.csv` (antes ≈ 9.847 ms a quente).
