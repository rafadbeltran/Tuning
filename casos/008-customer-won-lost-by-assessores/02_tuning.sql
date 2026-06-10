-- =============================================================
-- Tuning — aplicar em ordem e re-rodar o EXPLAIN ANALYZE.
-- Caso: intranet.customer (~3,96M linhas) — won/lost por lista de assessores.
-- Baseline: full table scan de 3,96M para reter 7.047 (~9,8 s a quente).
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 0 — verificar a sutileza semântica antes de reescrever.
--
-- O OR cruzado do original aceita combinações "trocadas" (ganhou por um assessor,
-- mas casou pela data em que perdeu). Isso só ocorre se houver linhas com won_date
-- E lost_date ambos preenchidos. Se este COUNT for ~0, o UNION ALL de 2 ramos
-- abaixo é EQUIVALENTE ao original; se não, ver a variante fiel (4 ramos) no fim.
-- -------------------------------------------------------------
-- SELECT COUNT(*) AS ambas_datas
-- FROM intranet.customer
-- WHERE status IN ('won','lost')
--   AND won_date IS NOT NULL
--   AND lost_date IS NOT NULL;


-- -------------------------------------------------------------
-- PASSO 1 (prioritário): um índice composto por ramo.
--   (won_by_id, won_date)   -> serve o ramo "won": IN de assessores + range de data.
--   (lost_by_id, lost_date) -> serve o ramo "lost".
-- Com won_by_id IN (54 ids), vira 54 range scans por won_date (em vez de full scan).
-- (Confirmar tipos no SHOW CREATE TABLE; se *_by_id for INT, o IN com literais entre
--  aspas é coagido para INT e continua sargável — não há wrapping da coluna.)
-- -------------------------------------------------------------
CREATE INDEX idx_customer_wonby_wondate   ON intranet.customer (won_by_id,  won_date);
CREATE INDEX idx_customer_lostby_lostdate ON intranet.customer (lost_by_id, lost_date);
-- Opcional: incluir status para filtrá-lo no índice (won_by_id, won_date, status).


-- -------------------------------------------------------------
-- PASSO 2: reescrita com CTE + UNION ALL — um ramo won, um ramo lost.
-- A lista de assessores (56 ids) fica num CTE `assessores`, definida UMA vez em vez
-- de repetida nos dois ramos. Os ramos são MUTUAMENTE EXCLUSIVOS por status
-- ('won' x 'lost'), então UNION ALL (sem dedup) é seguro; cada ramo crava um índice
-- do PASSO 1.
--
-- Avisos:
--   - CTE com VALUES ROW(...) exige MySQL 8.0.19+.
--   - won_by_id/lost_by_id são NUMÉRICOS (confirmado pelo plano: aparecia
--     `cast(a.id as double)` quando os ids do CTE eram string, o que jogou o ramo
--     won para hash join em vez do índice composto). Por isso os ids abaixo estão
--     SEM aspas (numéricos) — assim os dois ramos usam o índice (col, data) direto.
--   - VALIDAR no EXPLAIN que cada ramo usa seu índice composto (idx_customer_*),
--     puxando a partir de `assessores`. Se o otimizador materializar/escanear, use a
--     lista literal `IN (...)` direto no WHERE (como no 00_consulta_original.sql).
--   - Projeção: a MESMA do 00 (59 colunas); uso c.* por brevidade.
--   - Datas: range half-open (>= dia 1 AND < dia 1 do mês seguinte), mais robusto que
--     o '<= ...23:59:59.999' do original.
-- -------------------------------------------------------------
WITH assessores (id) AS (
    VALUES
        ROW(3646),ROW(3398),ROW(3623),ROW(3487),ROW(3642),ROW(3635),ROW(3641),ROW(3408),
        ROW(3478),ROW(3472),ROW(3402),ROW(3624),ROW(3144),ROW(3399),ROW(3490),ROW(3409),
        ROW(3477),ROW(3480),ROW(3638),ROW(3400),ROW(3640),ROW(3140),ROW(3245),ROW(3485),
        ROW(3626),ROW(3115),ROW(3403),ROW(3475),ROW(3411),ROW(3637),ROW(3474),ROW(3633),
        ROW(2860),ROW(3420),ROW(3622),ROW(3631),ROW(3421),ROW(3422),ROW(3644),ROW(3489),
        ROW(3482),ROW(3415),ROW(3401),ROW(3484),ROW(3639),ROW(3473),ROW(3645),ROW(3423),
        ROW(3240),ROW(3476),ROW(3424),ROW(3634),ROW(3625),ROW(3486),ROW(3643),ROW(3425)
)
SELECT c.*            -- (mesma projeção do 00; trocar por lista explícita se preciso)
FROM intranet.customer c
JOIN assessores a ON a.id = c.won_by_id
WHERE c.won_date >= '2026-06-01 00:00:00'
  AND c.won_date <  '2026-07-01 00:00:00'
  AND c.status = 'won'

UNION ALL

SELECT c.*
FROM intranet.customer c
JOIN assessores a ON a.id = c.lost_by_id
WHERE c.lost_date >= '2026-06-01 00:00:00'
  AND c.lost_date <  '2026-07-01 00:00:00'
  AND c.status = 'lost';


-- -------------------------------------------------------------
-- VALIDAÇÃO — re-rodar EXPLAIN ANALYZE e conferir:
--   - cada ramo usando seu índice (idx_customer_wonby_wondate / _lostby_lostdate)
--     via "Index range scan" / múltiplos lookups, SEM "Table scan on customer";
--   - tempo caindo de ~9,8 s para a casa de ms (lê só ~7k linhas, não 3,96M);
--   - conferir que a contagem de linhas bate com o original.
-- -------------------------------------------------------------


-- -------------------------------------------------------------
-- VARIANTE FIEL (só se o PASSO 0 achar linhas com as duas datas preenchidas):
-- reproduzir as 4 combinações de A AND B com UNION (DISTINCT, para deduplicar
-- linhas que casem em mais de uma combinação). Mais cara, mas 100% equivalente:
--   ramo1: won_by_id ∈ L  AND won_date  ∈ R
--   ramo2: won_by_id ∈ L  AND lost_date ∈ R
--   ramo3: lost_by_id ∈ L AND won_date  ∈ R
--   ramo4: lost_by_id ∈ L AND lost_date ∈ R
--   (todas AND status IN ('won','lost'))
-- Preferir resolver a origem (por que um deal teria won_date E lost_date?).
-- -------------------------------------------------------------
