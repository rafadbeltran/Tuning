# Diagnóstico

## EXPLAIN ANALYZE da consulta original (~8,86 s a quente)

```
-> Sort: done_time DESC  (cost=449707 rows=4.06e+6) (actual time=8857..8857 rows=317 loops=1)
    -> Filter: ((is_deleted = 0) and (user_id in (...42 ids...))
                and (done_time >= '2026-06-09 00:00:00') and (done_time <= '2026-06-09 23:59:59.999')))
       (cost=449707 rows=4.06e+6) (actual time=8853..8856 rows=317 loops=1)
        -> Table scan on activities  (cost=449707 rows=4.06e+6) (actual time=3.67..8402 rows=4.46e+6 loops=1)
```

## Problema principal: falta índice em `(user_id, done_time)` → full table scan

A consulta varre **~4,46 milhões de linhas** (`Table scan on activities`, ~8,4 s) para
reter **317** (~0,007%). O filtro é muito seletivo (42 usuários, um único dia,
`is_deleted = 0`), mas **não há índice** que o atenda, então o otimizador varre tudo.

> A frio isso tende a custar **minutos** (full scan de 4,46M do disco) — mesma
> assinatura dos casos [007](../007-pack-auc-ultimo-maior-auc/) e
> [008](../008-customer-won-lost-by-assessores/).

## A diferença deste caso: a query JÁ é sargável

Diferente do 006 (`LIKE` em data), 008 (`OR` cruzado) ou 001 (coerção de tipo), aqui
**não há nada travando o índice**: `done_time BETWEEN ...` é range puro, `user_id IN
(...)` é direto, `is_deleted = 0` é igualdade. O predicado está pronto para usar índice
— **só falta o índice existir**. Logo, o fix é **criar o índice, sem reescrever a
consulta**.

## O `Sort: done_time DESC` não é o gargalo

O `Sort` recebe só **317 linhas** — ordenar isso é instantâneo. Ele aparece com
`actual time=8857` apenas porque **espera** o scan+filter terminarem. Com o índice
liderado por `user_id`, a ordenação por `done_time` vem quase de graça (por usuário já
sai ordenada; resta um merge/sort minúsculo das 317 para o `ORDER BY` global — e no
caso de **um único `user_id`** (versão B) o índice resolve a ordem direto, sem filesort).

## Resultado após o tuning (índice `idx_activities_user_donetime`)

`EXPLAIN ANALYZE` depois (~3,87 ms a quente):

```
-> Sort: done_time DESC  (cost=156 rows=323) (actual time=3.8..3.87 rows=317 loops=1)
    -> Filter: (is_deleted = 0)  (actual time=0.0302..1.14 rows=317 loops=1)
        -> Index range scan on activities using idx_activities_user_donetime
           over (user_id = ... AND '2026-06-09' <= done_time < '2026-06-10') OR (40 more)
           (cost=156 rows=323) (actual time=0.0294..1.11 rows=317 loops=1)
```

| Métrica           | Antes                          | Depois                                       |
|-------------------|--------------------------------|----------------------------------------------|
| Acesso            | `Table scan`, **4,46M** linhas | `Index range scan` (42 ranges), **317**      |
| Estimativa × real | `rows=4.06e6` vs `317`         | `rows=323` vs `317` (bate)                   |
| Tempo (quente)    | **~8.857 ms**                  | **~3,87 ms** (~2.300×)                        |

Os 42 `user_id` viraram **42 range scans** no índice (um por usuário, já na janela do
dia), lendo só 317 linhas. O `Sort: done_time DESC` sobrou (filesort de 317 linhas,
~2,7 ms) — desprezível, como previsto; não vale um 2º índice para removê-lo. Como o
ganho vem de **deixar de varrer 4,46M**, vale também a frio.

> Pendente: medir a **frio** e, se quiser o critério frio→frio do 007, atualizar o
> `tempo_antes` no `metricas_casos.csv` (hoje registrado a quente).

## Pendências de informação

- `SHOW CREATE TABLE avel.activities` — PK, índices existentes (confirmar que não há
  já um índice por `user_id`/`done_time` a estender) e tipos das colunas.
