# Diagnóstico

## EXPLAIN ANALYZE da consulta original

```
-> Group (no aggregates)  (cost=716660 rows=3.54e+6) (actual time=103..8956 rows=4 loops=1)
    -> Filter: (<cache>('5584486420') member of (phones_list) or <cache>('fabricio_ruschel@hotmail.com') member of (emails_list))  (cost=362970 rows=3.54e+6) (actual time=76.9..8956 rows=4 loops=1)
        -> Index scan on leads_data_connections using idx_lead_id  (cost=362970 rows=3.54e+6) (actual time=0.0331..7494 rows=3.84e+6 loops=1)
```

## Problema principal: `MEMBER OF` sobre JSON não usa índice comum

A coluna `idx_lead_id` no plano **não está filtrando nada** — serve só como uma forma
de percorrer a tabela inteira (e de quebra entregar `lead_id` ordenado, o que ajuda o
`DISTINCT`/`Group`). O MySQL lê as **~3,84 milhões de linhas** e, para cada uma, avalia
o `MEMBER OF` nos dois arrays JSON (`phones_list`, `emails_list`). Resultado: **~8,96 s**
para devolver apenas **4 linhas**.

A estimativa `rows=3.54e+6` vs. o real `rows=4` confirma que o otimizador não tem
seletividade sobre essas colunas — sem índice, não há como evitar varrer tudo.

## Causa raiz

`MEMBER OF`, `JSON_CONTAINS` e `JSON_OVERLAPS` só conseguem usar índice se houver um
**índice multi-valor** (multi-valued index) sobre o array JSON. Sem ele, a única opção
do otimizador é o full scan + filtro linha a linha.

## Pontos secundários

- O `DISTINCT` (vira `Group (no aggregates)`) não é o gargalo: ele opera sobre o
  resultado já filtrado e o `idx_lead_id` entrega `lead_id` ordenado. O custo está
  inteiro na varredura.
- O `OR` entre duas colunas distintas é o que obriga a percorrer as duas listas. Com
  índices multi-valor, ele precisa virar `index_merge (union)` — ou ser reescrito como
  `UNION` para garantir que cada ramo use o seu índice (ver [`02_tuning.sql`](02_tuning.sql)).

## Pré-requisitos / cuidados

- **Índice multi-valor exige MySQL 8.0.17+.** Como o plano usa o formato de árvore do
  `EXPLAIN ANALYZE` (8.0.18+), o recurso está disponível.
- O literal vem entre aspas (`"5584486420"`), então os valores são **string** → o CAST
  é para `CHAR(N) ARRAY`. O `N` precisa comportar o maior valor do array, senão o
  `CREATE INDEX` aborta ao varrer os dados existentes:
  `[22001][3907] Data too long for functional index`. Medir o maior elemento antes
  (ver [`02_tuning.sql`](02_tuning.sql)).
- Um índice multi-valor só admite **uma** coluna JSON; por isso são dois índices
  separados (`phones_list` e `emails_list`), não um composto.

## Resultado após o tuning

Solução final em duas frentes:
- **telefone**: índice multi-valor `idx_ldc_phones` (`CAST(phones_list AS CHAR(120) ARRAY)`);
- **e-mail**: o MV index não constrói (blob super-mesclado de 241 e-mails em ~324 leads
  estoura o limite por registro — erro 3906). Resolvido por tabela de lookup normalizada
  `bi.leads_emails` (índice B-tree), sincronizada via outbox + EVENT
  (ver [`02_tuning.sql`](02_tuning.sql), PASSO 2).
- **consulta**: reescrita com `UNION` (não `OR`).

### Lição: `OR` x `UNION`

A primeira tentativa de consulta usou `OR` (telefone `MEMBER OF` **OR** e-mail na lookup).
O otimizador **não combina** um `MEMBER OF` (MV index) com a subquery da lookup via
`index_merge` — caiu no full scan e ficou **pior que o original (~14,6 s)**:

```
-> Filter: (... member of (...) or <in_optimizer>(c.id in (select #2)))  (actual time=169..14619 rows=4)
    -> Index scan on c using idx_lead_id  (rows=3.84e+6) (actual time=3.08..11092)
```

Trocando para `UNION` (cada ramo usa o seu índice isoladamente):

```
-> Table scan on t  (actual time=0.0813..0.0823 rows=4 loops=1)
    -> Union materialize with deduplication  (actual time=0.0797..0.0797 rows=4)
        -> Filter: ... member of (cast(phones_list as char(120) array))  (actual time=0.044..0.0607 rows=4)
            -> Index lookup on leads_data_connections using idx_ldc_phones  (actual time=0.0425..0.0583 rows=4)
        -> Index lookup on leads_emails using PRIMARY (email='...')  (actual time=0.00855..0.0108 rows=4)
```

| Métrica       | Original            | `OR` (ruim)   | `UNION` (final)            |
|---------------|---------------------|---------------|----------------------------|
| Acesso        | full scan 3,84M     | full scan 3,84M | 2 index lookups (4 + 4 linhas) |
| Tempo total   | ~8.956 ms           | ~14.619 ms    | ~0,08 ms                   |

Ambos os índices confirmados em uso no plano final: `idx_ldc_phones` (telefone) e
`PRIMARY (email, conn_id)` da `leads_emails` (e-mail).
