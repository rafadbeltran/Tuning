# Diagnóstico

## EXPLAIN da consulta original

| id | select_type  | table             | type   | key                        | rows    | filtered | Extra                      |
|----|--------------|-------------------|--------|----------------------------|---------|----------|----------------------------|
| 1  | SIMPLE       | n                 | ref    | fk_notification__types_idx | 657.730 | 9        | Using where                |
| 1  | SIMPLE       | nn                | ref    | idx_nn_notif_user          | 1       | 100      | Using index                |
| 1  | SIMPLE       | <subquery2>       | eq_ref | <auto_distinct_key>        | 1       | 100      | Using where; Not exists    |
| 2  | MATERIALIZED | users_usuario     | ALL    | (nenhum)                   | 1.978   | 100      | Using where                |

## Problema principal: coerção de tipo em `status_id_virt`

`status_id_virt` é `varchar(50)`, mas a consulta compara com o inteiro `0`:

```sql
WHERE n.status_id_virt = 0      -- varchar comparado com número
```

O MySQL converte TODOS os valores da coluna para float antes de comparar, o que
inviabiliza qualquer seek por índice sobre essa coluna. Resultado: o otimizador
ignora `idx_notif_otimizacao`/`idx_notif_type_id` e varre ~657 mil linhas só com
`type` (`fk_notification__types_idx`).

## Pontos secundários

- O antijoin do `NOT IN` já está saudável (materializado + `Not exists`, ~1.978 linhas).
  Não é o gargalo. CTE não traz ganho aqui; o otimizador já materializa a lista uma vez.
- `deadline_time_virt` não está em índice nenhum e é recalculada (str_to_date) na
  leitura — só relevante se quisermos cobertura total.

## Resultado após o tuning (Passo 1: `= '0'`)

Apenas corrigir a coerção de tipo (`= 0` → `= '0'`) destravou o índice
`idx_notif_otimizacao`. Não foi preciso criar índice novo.

`EXPLAIN ANALYZE` depois da correção:

```
-> Nested loop antijoin (cost=15 rows=9.6) (actual time=4.53..4.53 rows=0 loops=1)
   -> Nested loop inner join (cost=11.6 rows=9.6) (actual time=4.47..4.51 rows=3 loops=1)
      -> Filter: status_id_virt='0' AND type=3 AND schedule_id_virt<>43
         (cost=3.66 rows=7) (actual time=3.86..3.9 rows=6 loops=1)
         -> Index range scan on n using idx_notif_otimizacao (actual rows=6 loops=1)
      -> Covering index lookup on nn using idx_nn_notif_user (rows=0.5 loops=6)
   -> Filter: is_active=1 AND role_id IN (142,165,174) (rows=1 loops=3)
      -> Single-row index lookup on users_usuario PRIMARY (rows=1 loops=3)
```

| Métrica       | Antes                                          | Depois                                  |
|---------------|------------------------------------------------|-----------------------------------------|
| Acesso a `n`  | `ref` em `fk_notification__types_idx`, ~657.730 linhas | range scan em `idx_notif_otimizacao`, 6 linhas |
| Tempo total   | —                                              | ~4,53 ms                                |

A estimativa (7 linhas) bateu com o real (6) — não era otimista.

**Nota de correção (não é performance):** o `rows=0` final é dos dados atuais —
o inner join trouxe 3 linhas e o antijoin removeu as 3 (esses `user_id`
estavam no conjunto excluído). Validar uma vez com dados em que se espera
retorno, para confirmar a lógica.


# Quem Roda?
dist_100k_mais	10.1.1.244:49362