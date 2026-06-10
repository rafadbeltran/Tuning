# 007 — `bi.pack_auc` — maior/último AUC por cliente (`big_team = 'spitfire'`)

**Status:** 🟢 Resolvido — coluna gerada `data_d DATE` **STORED** (a `data` era `TEXT`)
+ índices `(cliente, data_d)` e `(cliente, auc, data_d)` + reescrita com `JOIN LATERAL`
eliminaram os 4 full scans de 2,69M e a subquery correlacionada: **~11.607 ms → ~770 ms
(~15×)**, com `data_max_auc` correto. (Tentar VIRTUAL causou regressão de `0000-00-00`
por índice de coluna virtual stale — daí o `STORED`.) Pendências de negócio (semântica
do empate de AUC) e estrutural (PK) seguem anotadas.

Para os clientes do time `spitfire`, devolver o **maior AUC** por cliente e a **data**
associada. Há duas iterações no baseline: a versão A (agora completa) e a versão B
com dois *derived tables* (a perfilada).

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline (versões A e B).
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — índices + reescrita preservando a semântica.

## Resumo do diagnóstico

`bi.pack_auc` (~2,69M linhas) **sem índice útil** → é varrida **4×**: filtro
`big_team='spitfire'` (+ `Sort: cliente`), `MAX(data)` por cliente (temp table),
`MAX(auc)` por cliente (temp table) e a **subquery correlacionada na projeção**
(`data_max_auc`) que faz table scan **por linha de saída** (`loops=1000`). Total
**~11,6 s a quente** — e **~21 min a frio** na 1ª execução (assinatura de full scan).

## ⚠️ Bloqueador descoberto: `data` é coluna `TEXT` (data como string)

`CREATE INDEX` falhou com `[1170] ... 'data' used in key specification without a key
length`. A coluna `data` é **`TEXT`**, não `DATE`. Além de não indexar sem prefixo,
`MAX(data)`/`=` são **lexicográficos** → só corretos se o formato for ISO
`YYYY-MM-DD`. Resolver o tipo é **pré-requisito** (e é correção, não só performance).

## Ordem de ataque

0. **Resolver o tipo de `data`** (ver `02_tuning.sql`): caminho A = índice de prefixo
   `data(10)` (band-aid, só ISO); caminho B (recomendado) = coluna gerada `data_d DATE`
   + índices nela, sem quebrar o ETL.
1. Índices `(cliente, data_d)` e `(cliente, auc, data_d)` — o 1º transforma `MAX`
   em *loose index scan*; o 2º resolve "maior AUC + data dele" numa *index dive*
   covering por cliente (mata os scans #3 e #4).
2. Reescrita: `latest` (registro da última data, filtrado spitfire **antes**) +
   `JOIN LATERAL` para o maior AUC só dos clientes spitfire — 1 passada por cliente,
   sem dupla agregação nem subquery correlacionada.

## Pendências

- [x] Completar a versão A truncada no `00`.
- [x] `EXPLAIN ANALYZE` lido e diagnóstico registrado.
- [x] Confirmado: `data` é `TEXT` ISO `YYYY-MM-DD HH:MM:SS`; `auc` é `double` (sem bug).
- [x] Caminho B aplicado (coluna gerada `data_d DATE` + 2 índices).
- [x] Reescrita aplicada, `EXPLAIN ANALYZE` "depois" colado (11.607 ms → 770 ms, STORED).
- [x] Regressão `0000-00-00` resolvida: índice de coluna **VIRTUAL** servia valor stale
      em leitura covering → migrado `data_d` para **STORED**; resultado validado correto.
- [x] Desempate do `max_auc`: definido **data mais antiga** (`ORDER BY auc DESC, data_d ASC`)
      para reproduzir o que a original (LIMIT 1 sem ORDER BY) devolve. Spot-check OK —
      resultado batendo a original (cliente 1881 = dia 28 etc.).
- [x] `metricas_casos.csv` preenchido.
- [ ] **Regra de negócio:** confirmar se `max_auc` deve ser o pico histórico (atual)
      ou o AUC da última data ("foto"). A reescrita preserva o comportamento atual.
- [x] **Zero-date (`0000-00-00`) investigado e resolvido:** a origem é uniforme e
      limpa (2.688.181 linhas, todas ISO `YYYY-MM-DD HH:MM:SS`); os zeros vinham de
      máscara incorreta numa tentativa anterior, não dos dados. Com `'%Y-%m-%d %H:%i:%s'`
      a conversão não gera nenhum zero. Versão robusta mantida como rede de segurança.
- [x] Conversão validada: 2.688.181 linhas, **0 nulos, 0 zero-dates**, range
      `2020-11-30` → `2026-04-30`. Perf (896 ms) inalterada (índice guarda os mesmos
      valores de `data_d`).
- [ ] **Estrutural (à parte):** `pack_auc` não tem PRIMARY KEY nem índices — avaliar
      adicionar uma PK (beneficia replicação e todo acesso à tabela).
- [ ] (Opcional) indexar/normalizar `big_team` para filtrar spitfire antes do skip scan.
