# 003 — `MEMBER OF` em colunas JSON (`leads_data_connections`) (MySQL / InnoDB)

**Status:** 🟢 Resolvido — telefone por índice multi-valor `idx_ldc_phones`, e-mail por
tabela de lookup `bi.leads_emails`, consulta reescrita com `UNION`. De ~8,96 s para
~0,08 ms (a versão intermediária com `OR` chegou a piorar para ~14,6 s — ver diagnóstico).

Tuning de uma consulta sobre `bi.leads_data_connections` (~3,84 milhões de linhas) que
busca `lead_id` por um telefone OU um e-mail guardados em colunas JSON (`phones_list`,
`emails_list`). Hoje faz full scan + `MEMBER OF` linha a linha (~8,96 s para 4 linhas).

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN ANALYZE e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — solução completa: índice multi-valor do telefone +
  estrutura de e-mail (lookup + outbox + EVENT + interruptor) + consulta com UNION.
- [`03_procedure.sql`](03_procedure.sql) — consulta final parametrizada como procedure.

## Resumo do diagnóstico

`MEMBER OF` sobre coluna JSON não usa índice comum. O `idx_lead_id` só serve para
percorrer a tabela inteira (3,84M linhas) enquanto o filtro JSON roda linha a linha —
~8,96 s para retornar 4 linhas. A solução base é **índice multi-valor** sobre os arrays
(`CAST(... AS CHAR(N) ARRAY)`), que `MEMBER OF` consegue usar.

### Telefone (resolvido)

`idx_ldc_phones` (`CAST(phones_list AS CHAR(120) ARRAY)`) criado com sucesso.

### E-mail (bloqueado por dado, encaminhado)

O MV index de e-mail **não constrói**: ~324 leads carregam um mesmo blob super-mesclado
de **241 e-mails distintos e reais** (bug de resolução de identidade), que estoura o
limite de tamanho por registro do MV index (erro 3906). Não é duplicação — deduplicar
não resolve. Como o blob é único e isolado (resto da tabela tem ≤ 115 e-mails/linha),
duas saídas:

- **(B) escolhida:** tabela de lookup normalizada `bi.leads_emails` com índice B-tree,
  imune ao limite do MV index. Sincronização **assíncrona** (outbox + EVENT) para não
  pesar no caminho de escrita (cenário com muitos inserts). Ver
  [`02_tuning.sql`](02_tuning.sql) (PASSO 2).
- (A) alternativa: limpar/quarentenar os 324 registros super-mesclados (depende do dono
  do dado) e então construir o MV index de e-mail.

## Ordem de ataque

1. Telefone: `idx_ldc_phones` (feito).
2. E-mail: aplicar a Opção B (tabelas → backfill → triggers → EVENT → consulta).
3. Reescrever a consulta: telefone via MV index + e-mail via lookup.
4. Reportar o blob super-mesclado (241 e-mails em ~324 leads) ao dono do dado.

## Pendências

- [x] Confirmar a versão do MySQL (≥ 8.0.17) e medir o maior telefone/e-mail.
- [x] `idx_ldc_phones` criado (`CHAR(120)`).
- [x] Aplicar a Opção B e re-rodar o `EXPLAIN ANALYZE` da consulta reescrita.
- [x] Medir antes/depois e registrar os números (ver [01_diagnostico.md](01_diagnostico.md)).
- [ ] Definir cadência do ETL (append vs update/delete) e tolerância de atraso (~30s ok?).
- [ ] Reportar o dado super-mesclado (bug de merge) na origem.
