DELIMITER $$

CREATE PROCEDURE intranet.sp_customer_won_lost_assessores (
    IN p_assessor_ids VARCHAR(2000),  -- CSV de ids: '3646,3398,...,3425'
    IN p_from         DATE,           -- início do período (inclusive)
    IN p_to           DATE            -- fim do período (inclusive)
)
BEGIN
    -- Versão FIEL do caso 008 (4 ramos), parametrizada — reproduz o original:
    --   (won_by_id ∈ L OR lost_by_id ∈ L)
    --   AND (won_date no período OR lost_date no período)
    --   AND status IN ('won','lost')
    -- Os 4 ramos cobrem as combinações do OR cruzado; UNION (distinct) deduplica.
    --
    -- A lista (CSV) é quebrada em linhas por um CTE recursivo e os ids são
    -- CAST para UNSIGNED — won_by_id/lost_by_id são NUMÉRICOS, então o tipo certo
    -- no JOIN mantém os índices (idx_customer_wonby_wondate / _lostby_lostdate).
    -- Passar string crua faria cast(... as double) e cegaria o índice (ver
    -- 01_diagnostico.md). Datas: range half-open [from, to+1dia) — robusto a
    -- fração de segundo.
    --
    -- Pré-requisitos: índices (won_by_id, won_date) e (lost_by_id, lost_date)
    -- do 02_tuning.sql. MySQL 8.0+ (CTE recursivo).
    WITH RECURSIVE assessores AS (
        SELECT
            CAST(TRIM(SUBSTRING_INDEX(p_assessor_ids, ',', 1)) AS UNSIGNED) AS id,
            CASE WHEN LOCATE(',', p_assessor_ids) > 0
                 THEN SUBSTRING(p_assessor_ids, LOCATE(',', p_assessor_ids) + 1) ELSE '' END AS resto
        UNION ALL
        SELECT
            CAST(TRIM(SUBSTRING_INDEX(resto, ',', 1)) AS UNSIGNED),
            CASE WHEN LOCATE(',', resto) > 0
                 THEN SUBSTRING(resto, LOCATE(',', resto) + 1) ELSE '' END
        FROM assessores
        WHERE resto <> ''
    )

    -- B1: assessor GANHOU o deal, data de GANHO no período
    SELECT c.* FROM intranet.customer c
    JOIN assessores a ON a.id = c.won_by_id
    WHERE c.won_date >= p_from AND c.won_date < p_to + INTERVAL 1 DAY
      AND c.status IN ('won','lost')

    UNION

    -- B2 (cruzado): assessor GANHOU, casou pela data de PERDA no período
    SELECT c.* FROM intranet.customer c
    JOIN assessores a ON a.id = c.won_by_id
    WHERE c.lost_date >= p_from AND c.lost_date < p_to + INTERVAL 1 DAY
      AND c.status IN ('won','lost')

    UNION

    -- B3 (cruzado): assessor PERDEU, casou pela data de GANHO no período
    SELECT c.* FROM intranet.customer c
    JOIN assessores a ON a.id = c.lost_by_id
    WHERE c.won_date >= p_from AND c.won_date < p_to + INTERVAL 1 DAY
      AND c.status IN ('won','lost')

    UNION

    -- B4: assessor PERDEU o deal, data de PERDA no período
    SELECT c.* FROM intranet.customer c
    JOIN assessores a ON a.id = c.lost_by_id
    WHERE c.lost_date >= p_from AND c.lost_date < p_to + INTERVAL 1 DAY
      AND c.status IN ('won','lost');
END $$

DELIMITER ;

-- Como chamar:
--   CALL intranet.sp_customer_won_lost_assessores(
--       '3646,3398,3623,3487,3642,3635,3641,3408,3478,3472,3402,3624,3144,3399,3490,3409,3477,3480,3638,3400,3640,3140,3245,3485,3626,3115,3403,3475,3411,3637,3474,3633,2860,3420,3622,3631,3421,3422,3644,3489,3482,3415,3401,3484,3639,3473,3645,3423,3240,3476,3424,3634,3625,3486,3643,3425',
--       '2026-06-01',
--       '2026-06-30'
--   );
--
-- Variante "intent" (2 ramos, sem os cruzados B2/B3): manter só B1 e B4 e trocar
-- status IN ('won','lost') por status='won' (B1) e status='lost' (B4) -> UNION ALL.
