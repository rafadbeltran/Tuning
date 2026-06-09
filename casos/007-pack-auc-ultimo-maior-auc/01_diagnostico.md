# Diagnóstico

> Plano da **versão B** (a reescrita com dois derived tables + subquery
> correlacionada + `ORDER BY cliente LIMIT 1000`).

## EXPLAIN ANALYZE da consulta original (~11,6 s)

```
-> Limit: 1000 row(s)  (cost=4.03e+6 rows=0) (actual time=11566..11607 rows=1000 loops=1)
    -> Nested loop inner join  (actual time=11566..11607 rows=1000 loops=1)
        -> Nested loop inner join  (actual time=8857..8885 rows=1000 loops=1)
            -> Sort: cliente  (actual time=5086..5091 rows=6142 loops=1)
                -> Filter: ((p.big_team = 'spitfire') and (p.cliente is not null))  (actual time=3960..5076 rows=23601 loops=1)
                    -> Table scan on p  (rows=2.51e+6) (actual time=2.94..4867 rows=2.69e+6 loops=1)   -- SCAN #1
            -> Filter: (ld.max_data = p.data)  (actual time=0.617 rows=0.163 loops=6142)
                -> Index lookup on ld using <auto_key0> (cliente=p.cliente)
                    -> Materialize  (actual time=3771 rows=96196 loops=1)
                        -> Aggregate using temporary table  (actual time=3676 rows=96196 loops=1)
                            -> Table scan on pack_auc  (actual time=..1469 rows=2.69e+6 loops=1)        -- SCAN #2 (MAX(data))
        -> Index lookup on m using <auto_key0> (cliente=p.cliente)  (actual time=2.71 rows=1 loops=1000)
            -> Materialize  (actual time=2709 rows=96196 loops=1)
                -> Aggregate using temporary table  (actual time=2643 rows=96196 loops=1)
                    -> Table scan on pack_auc  (actual time=..1418 rows=2.69e+6 loops=1)                -- SCAN #3 (MAX(auc))
-> Select #2 (subquery in projection; dependent)
    -> Limit: 1 row(s)  (actual time=1301 rows=1 loops=1000)
        -> Filter: ((pack_auc.cliente = p.cliente) and (pack_auc.auc = m.max_auc))  (actual time=1301 rows=1 loops=1000)
            -> Table scan on pack_auc  (rows=2.51e+6) (actual time=..1162 rows=2.17e+6 loops=1000)      -- SCAN #4 (dependente, por linha!)
```

## Problema principal: zero índices úteis → `pack_auc` (2,69M linhas) varrida 4×

A tabela não tem índice que sirva a nenhum dos acessos. O otimizador cai em **table
scan** toda vez:

| # | Para quê | Custo observado |
|---|----------|-----------------|
| SCAN #1 | filtrar `big_team='spitfire'` (`p`) | 2,69M lidas → 23.601, depois `Sort: cliente` (~5 s) |
| SCAN #2 | derived `ld` = `MAX(data)` por cliente | 2,69M + `Aggregate using temporary table` → 96.196 (~3,8 s) |
| SCAN #3 | derived `m` = `MAX(auc)` por cliente | 2,69M + `temporary table` → 96.196 (~2,7 s) |
| SCAN #4 | subquery **dependente** `data_max_auc` | table scan de ~2,17M **por linha de saída** (`loops=1000`) |

O SCAN #4 é o mais venenoso: a subquery correlacionada `(SELECT data ... WHERE cliente
= s.cliente AND auc = m.max_auc LIMIT 1)` está **na projeção**, então roda **uma vez
por linha do resultado** — 1000 full scans potenciais. Só não explode em minutos
porque o `LIMIT 1000` corta cedo (note `rows=6142` no Sort, não os 23.601).

Repare também que `cost ... rows=0` no topo: o otimizador nem consegue estimar a
cardinalidade direito (sinal clássico de ausência de estatística/índice).

## Por que a versão B não ajudou

Separar "última data" (`ld`) e "maior AUC" (`m`) em dois derived tables **dobrou** o
trabalho de agregação (SCAN #2 + SCAN #3, cada um materializando 96.196 linhas) e
ainda manteve a subquery correlacionada (SCAN #4). É mais código fazendo mais
varreduras.

## Observação de regra de negócio (a confirmar — não muda o plano, muda o resultado)

A consulta mistura três "instantes" diferentes na mesma linha:

- `assessor` / `big_team` → vêm do registro da **última data** (`ld`).
- `max_auc` → é o **MAX(auc) de todo o histórico** do cliente (`m`).
- `data_max_auc` → é a **data do maior AUC histórico** (subquery).

Ou seja, `max_auc` **não** é o AUC da última data; é o pico histórico. Se a intenção
real for "foto da última data", a query está retornando outra coisa. A reescrita do
[`02_tuning.sql`](02_tuning.sql) **preserva o comportamento atual** (ethos do repo:
tunar sem mudar semântica) e deixa essa decisão como pendência de negócio.

## Descoberta ao aplicar: `data` é coluna `TEXT` guardando uma data

O `CREATE INDEX` falhou com **`[1170] BLOB/TEXT column 'data' used in key
specification without a key length`** — ou seja, a coluna `data` é **`TEXT`** (não
`DATE`/`DATETIME`), apesar de armazenar literalmente uma data.

Isso tem dois efeitos, e o segundo é **correção**, não performance:

1. **Indexação:** `TEXT` não indexa sem comprimento de prefixo (`data(N)`), e índice
   de prefixo tem limitações (ordenação/cobertura).
2. **Correção (grave):** `MAX(data)` e `p.data = ld.max_data` são comparações
   **lexicográficas** (byte a byte), não cronológicas. Só dão o resultado certo se o
   formato for **`YYYY-MM-DD` zero-padded (ISO)**. Em `DD/MM/YYYY`, `D/M/YYYY` etc., a
   "última data" sai **errada** silenciosamente.

→ A correção de raiz não é só índice: é **tipar a coluna como `DATE`** (ou adicionar
uma coluna gerada `DATE` indexada, sem quebrar o ETL). Ver caminhos A/B no
[`02_tuning.sql`](02_tuning.sql).

### Confirmado pelo `SHOW CREATE TABLE`

```
`big_team` text,        -- filtro 'spitfire' sobre TEXT
`cliente`  bigint,      -- OK, lidera os índices
`data`     text,        -- data como string, formato ISO 'YYYY-MM-DD HH:MM:SS'
`auc`      double,      -- OK: MAX(auc) numérico, sem bug lexicográfico
...
ENGINE=InnoDB           -- SEM PRIMARY KEY e SEM NENHUM ÍNDICE
```

- **`data`**: formato ISO `YYYY-MM-DD HH:MM:SS` (ex.: `2020-11-30 00:00:00`). Como é
  ISO zero-padded, `MAX(data)` lexicográfico **bate com o cronológico hoje** — está
  certo por sorte, mas é frágil. Vira `data_d DATE` (coluna gerada) no tuning.
- **`auc` é `double`** → sem problema de ordenação; o índice `(cliente, auc, …)` serve.
- **A tabela não tem PRIMARY KEY nem índice nenhum.** É a causa de *todo* acesso a
  `pack_auc` ser full scan — não só desta query. Recomendado adicionar uma PK
  (beneficia replicação e qualquer consulta na tabela), à parte deste caso.

### Armadilha da conversão: zero-date (`0000-00-00`)

Ao criar `data_d` com `STR_TO_DATE(\`data\`, '%Y-%m-%d %H:%i:%s')`, **muitas linhas
viraram `0000-00-00`**.

**Resolvido — era máscara, não dado.** A query de "forma" (dígito→9, letra→X) provou
que a origem é **uniforme e limpa**:

```
forma                  len   n
9999-99-99 99:99:99    19    2.688.181    (ex.: 2020-11-30 00:00:00)
```

Uma única forma, ISO `YYYY-MM-DD HH:MM:SS`, em todas as 2,69M linhas — sem formato
misturado nem caractere oculto. E o filtro `data_d IS NULL OR = '0000-00-00'` não
retornou nenhuma linha. Ou seja, com a máscara correta `'%Y-%m-%d %H:%i:%s'` a
conversão **não gera zero-date algum**.

→ Os `0000-00-00` observados antes vieram de uma **tentativa com máscara incorreta**
(ex.: `'%Y-%m-%d'` truncando o horário, ou separador/`%y` trocado), não dos dados.

**Lição:** a comparação lexicográfica do TEXT mascarava qualquer problema de
formato; ao tipar para `DATE`, a máscara do `STR_TO_DATE` precisa casar exatamente —
e vale validar a conversão (`SUM(data_d IS NULL)`, `SUM(YEAR(data_d)=0)`) antes de
confiar. A versão robusta (lixo → `NULL`) fica como rede de segurança no
[`02_tuning.sql`](02_tuning.sql), mesmo que aqui não haja lixo a tratar.

**Validação final:** 2.688.181 linhas, `nulos = 0`, `zero_dates = 0`, datas de
`2020-11-30` a `2026-04-30`.

### Regressão: `data_max_auc = 0000-00-00` via índice de coluna VIRTUAL stale

Mesmo com `data_d` validado (full scan recalcula → 0 zeros), a **query tunada**
devolvia `data_max_auc = 0000-00-00` em muitas linhas. Causa raiz:

- O `LATERAL` seleciona **só `auc` e `data_d`** → ambos cabem no índice
  `(cliente, auc, data_d)` → leitura **100% covering**: o MySQL devolve o `data_d`
  **direto do índice, sem recalcular** a expressão da coluna gerada.
- Esse índice estava com **valor stale** (construído sob uma definição anterior da
  coluna). Sharp edge conhecido de **índice sobre coluna gerada VIRTUAL**.
- Por que enganou: um teste que também selecionava `\`data\`` (fora do índice) forçava
  ir à linha base e **recalcular** `data_d` → vinha correto. A validação por full
  scan idem. Só a leitura **covering** expunha o lixo do índice.

**Correção:** reconstruir os índices (`DROP`/`ADD`) — recomputam do estado atual — e/ou
trocar `data_d` para **`STORED`** (materializa na linha; imune a esse problema). Ver
[`02_tuning.sql`](02_tuning.sql).

**Resolução aplicada:** trocada `data_d` para **`STORED`** (drop índices → drop coluna
→ recriar `STORED` → recriar índices). A query tunada passou a devolver `data_max_auc`
correto (sem `0000-00-00`), com plano idêntico em forma e **~770 ms** — o ganho de
~15× se mantém, agora com resultado validado.

**Lição (forte):** índice sobre **coluna gerada VIRTUAL** pode servir valor
desatualizado em leitura **covering** se a definição mudou sem reconstrução. Ao mexer
na expressão de uma generated column indexada, **reconstrua o índice** — ou prefira
`STORED` quando a coluna for chave de índice crítica.

## Resultado após o tuning (coluna gerada `data_d` + 2 índices + reescrita)

`EXPLAIN ANALYZE` depois (versão final, `data_d` **STORED**, ~770 ms):

```
-> Limit: 1000  (actual time=770..770 rows=1000 loops=1)
    -> Sort: l.cliente  (actual time=770..770 rows=1000 loops=1)
        -> Stream results  (actual time=283..767 rows=3604 loops=1)
            -> Nested loop inner join  (actual time=283..762 rows=3604 loops=1)
                -> Nested loop inner join  (actual time=283..698 rows=3604 loops=1)
                    -> Materialize CTE ld  (actual time=283..283 rows=96196 loops=1)
                        -> Covering index skip scan for grouping on pack_auc using idx_pack_auc_cliente_datad  (actual time=0.024..255 rows=96196 loops=1)   -- MAX(data_d) via índice
                    -> Index lookup on p using idx_pack_auc_cliente_datad (cliente, data_d) + Filter big_team='spitfire'  (rows=1 loops=96196)   -- 96.196 -> 3.604
                -> Materialize (LATERAL mx)  (loops=3604)
                    -> Limit 1 / Sort auc DESC, data_d DESC
                        -> Index lookup on p2 using idx_pack_auc_cliente_auc_datad (cliente)  (actual time=0.002..0.012 rows=20.2 loops=3604)   -- maior AUC + data, 1 dive/cliente
```

| Métrica            | Antes                                          | Depois                                            |
|--------------------|------------------------------------------------|---------------------------------------------------|
| Acesso a `pack_auc`| **4 table scans** de 2,69M + subquery dependente | skip scan (MAX) + 2 index lookups               |
| `MAX(data)`        | full scan + `temporary table`                  | `Covering index skip scan for grouping`           |
| `max_auc` + data   | full scan (`m`) + subquery **por linha** (`loops=1000`) | `JOIN LATERAL`: index dive em `(cliente,auc,data_d)`, 1×/cliente |
| Tempo              | **~11.607 ms**                                 | **~770 ms** (~15×)                                |

Os três cânceres do plano antigo foram extirpados: dupla agregação, `temporary table`
e a subquery correlacionada na projeção.

### Onde ainda dá pra raspar (opcional)

O custo dominante agora é o `Materialize CTE ld` (~320 ms): o skip scan calcula
`MAX(data_d)` para **todos** os 96.196 clientes, mas só 3.604 são spitfire. Como o
time vem do registro mais recente, não dá pra filtrar antes — a menos que `big_team`
seja indexável (hoje é `TEXT`). Um índice liderando por `big_team` (prefixo) ou
normalizar o time num `team_id` permitiria começar pelos ~23,6k registros spitfire em
vez de varrer 96k grupos. Ganho marginal perto do 13× já obtido; fica de nota.
