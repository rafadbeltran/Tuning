# Diagnóstico

## EXPLAIN ANALYZE da consulta original (~9,8 s a quente)

```
-> Filter: (((won_by_id in (...56 ids...)) or (lost_by_id in (...56 ids...)))
            and (((lost_date >= '2026-06-01') and (lost_date <= '2026-06-30 23:59:59.999'))
              or ((won_date  >= '2026-06-01') and (won_date  <= '2026-06-30 23:59:59.999')))
            and (status in ('won','lost')))
   (cost=384827 rows=102520) (actual time=6033..9847 rows=7047 loops=1)
    -> Table scan on customer  (cost=384827 rows=3.26e+6) (actual time=0.0373..9511 rows=3.96e+6 loops=1)
```

## Problema principal: `OR` cruzado entre colunas → full table scan

A consulta varre **~3,96 milhões de linhas** (`Table scan on customer`, ~9,5 s) para
reter **7.047** (~0,18%). O otimizador não usa índice nenhum por causa dos **dois `OR`
cruzando colunas diferentes**:

- `won_by_id IN (...) OR lost_by_id IN (...)` — `OR` entre **duas colunas**.
- `(won_date BETWEEN ...) OR (lost_date BETWEEN ...)` — `OR` entre **duas colunas**.

Um índice cobre uma coluna líder; com o `OR` espalhando o predicado por colunas
distintas (e ainda combinando os dois grupos), o otimizador desiste e cai em **full
scan**. A estimativa furada (`rows=102520` vs `7047` real) confirma a falta de um
caminho de índice útil.

> A frio (buffer pool vazio) isso tende a custar **minutos**, não ~10 s — mesma
> assinatura de full scan do caso [007](../007-pack-auc-ultimo-maior-auc/). Medir a 1ª
> execução real para registrar o número que dói.

## ⚠️ Sutileza semântica: o `OR` cruzado permite combinações "trocadas"

O `WHERE` é `A AND B AND C`, com `A` e `B` sendo `OR` independentes:

- `A = won_by_id ∈ L  OR  lost_by_id ∈ L`
- `B = won_date  ∈ R  OR  lost_date  ∈ R`
- `C = status ∈ {won, lost}`

`A AND B` expande em **quatro** combinações, incluindo as "trocadas":
`(won_by_id ∈ L AND lost_date ∈ R)` e `(lost_by_id ∈ L AND won_date ∈ R)`. Ou seja, a
query **aceita** uma linha casada pelo *assessor que ganhou* mas pela *data em que
perdeu* — provavelmente **não intencional** (artefato de filtro montado por GUI).

Na prática, isso só aparece se existirem linhas com **`won_date` e `lost_date` ambos
preenchidos**. Se cada deal tem só uma das datas (won OU lost, a outra `NULL`), as
combinações trocadas não casam e o `UNION ALL` de dois ramos é **equivalente** ao
original. **A confirmar** (ver verificação no [`02_tuning.sql`](02_tuning.sql)).

## Resultado após o tuning (1ª medição — CTE + UNION ALL)

`EXPLAIN ANALYZE` depois (~833 ms a quente):

```
-> Append  (actual time=14.5..833 rows=6962)
    -> [won]  Inner hash join (cast(a.id as double) = c.won_by_id)  (~21 ms, 1771 linhas)
              -> Materialize CTE assessores (56)
              -> Index range scan on c using idx_cust_won_date (won_date jun) + filter status='won' (2374->2330)
    -> [lost] Nested loop: assessores(56) -> Index lookup idx_customer_lostby_lostdate (lost_by_id, lost_date)  (~798 ms, 5191 linhas, 56 loops)
```

| Métrica         | Antes                         | Depois                                     |
|-----------------|-------------------------------|--------------------------------------------|
| Acesso          | full scan de **3,96M**        | índices por ramo (sem `Table scan`)        |
| Tempo (quente)  | **~9.847 ms**                 | **~833 ms** (~12×)                          |

### Dois pontos em aberto desta 1ª medição

1. **Contagem: 6.962 × 7.047 do original (−85).** São as linhas "cruzadas" da seção
   anterior — **confirmado que existem**. O `UNION ALL` de 2 ramos as descarta. Decidir
   **intent (2 ramos)** vs **fiel (4 ramos)** — provavelmente artefato de GUI.
2. **`cast(a.id as double)`:** os ids do CTE estavam como string e `*_by_id` é
   **numérico** → o ramo *won* caiu em **hash join** com o índice de data (`idx_cust_won_date`)
   em vez do composto. Ajustados os ids do CTE para numéricos no
   [`02_tuning.sql`](02_tuning.sql); re-medir (esperado o *won* também via índice
   composto, e o `cast` some).

### 2ª medição — versão FIEL (4 ramos) + ids numéricos: 7.047 linhas, ~135 ms

```
-> Table scan on <union temporary>  (actual time=132..135 rows=7047)
    -> Union materialize with deduplication  (rows=7047)
        -> [B1 won/won]   NL: idx_cust_won_date (won_date jun, 2374) -> lookup assessores  (~14 ms, 1772)
        -> [B2 won/lost]  NL: assessores -> idx_customer_wonby_wondate + filtro lost_date  (~45 ms, 118)
        -> [B3 lost/won]  NL: idx_cust_won_date (won_date jun) -> lookup assessores(lost_by_id)  (~10 ms, 54)
        -> [B4 lost/lost] NL: assessores -> idx_customer_lostby_lostdate  (~27 ms, 5222)
```

- **Contagem = 7.047 → idêntica ao original.** A versão de 4 ramos é o equivalente fiel.
- **~135 ms** a quente vs ~9.847 ms → **~73×**. (A versão de 2 ramos deu 6.962 / ~833 ms,
  mas os 833 ms eram artefato da coerção `cast` com ids string.)

### A lição: ids do CTE no tipo da coluna

Com os ids como **string**, o plano fazia `cast(a.id as double)` e o lado *lost*
demorava **~798 ms** (56 lookups arrastados). Com ids **numéricos** (tipo de
`won_by_id`/`lost_by_id`), o mesmo lado caiu para **~27 ms**. Tipo errado no IN/JOIN
cega o índice — mesma família dos casos [001](../001-notifications-status-id/) e
[007](../007-pack-auc-ultimo-maior-auc/).

> Pendente: decidir 2 ramos (intent, 6.962) vs 4 ramos (fiel, 7.047); medir a **frio**;
> preencher `metricas_casos.csv` (antes ≈ 9.847 ms a quente; a frio deve ser minutos).

## Pendências de informação

- `SHOW CREATE TABLE intranet.customer` — PK, índices existentes, tipo de
  `won_by_id`/`lost_by_id` (int vs varchar — o `IN` usa literais com aspas) e se
  `won_date`/`lost_date` aceitam NULL.
