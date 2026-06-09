# 005 — Leituras de tabela inteira sem filtro (`pipe_database`, `customer_info`)

**Status:** ⚪ Backlog

Duas consultas que varrem a tabela inteira: `avel.pipe_database` (projeção de 5
colunas, sem `WHERE`) e `avel.customer_info` (`SELECT *`, sem `WHERE`). Mesmo
diagnóstico, por isso ficam juntas.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.

## Suspeita (a confirmar com EXPLAIN)

- **Full table scan** por ausência de filtro. Se o consumidor (app/relatório) não
  precisa de *todas* as linhas, falta `WHERE`/paginação.
- `SELECT *` em `customer_info` traz colunas demais (custo de I/O e rede); reduzir à
  projeção realmente usada e avaliar **covering index** para o caso (A).
- Confirmar volume das tabelas — se forem pequenas e a leitura for um "dump"
  intencional para cache/ETL, pode ser comportamento aceitável (não é gargalo).

## Pendências

- [ ] `EXPLAIN` e volume (`SHOW TABLE STATUS`) das duas tabelas.
- [ ] Entender quem chama e se precisa de todas as linhas/colunas.
