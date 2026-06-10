DELIMITER $$

CREATE PROCEDURE avel.sp_activities_por_usuario_periodo (
    IN p_user_ids VARCHAR(4000),  -- CSV de user_id: '22226784,24390583,...'  (ou um só)
    IN p_from     DATE,           -- início do período (inclusive)
    IN p_to       DATE            -- fim do período (inclusive)
)
BEGIN
    -- Atividades concluídas no período, por lista de usuários, não deletadas,
    -- ordenadas por done_time DESC. Parametriza as versões A (lista) e B (um user).
    --
    -- A lista (CSV) é quebrada em linhas por um CTE recursivo e os ids são
    -- CAST para UNSIGNED — user_id é NUMÉRICO, então o tipo certo no JOIN mantém o
    -- índice (user_id, done_time): vira N range scans (um por usuário) já na ordem
    -- de done_time. Passar string crua faria coerção e cegaria o índice.
    -- Datas: range half-open [from, to+1dia) — robusto a fração de segundo.
    --
    -- Pré-requisito: índice (user_id, done_time) do 02_tuning.sql. MySQL 8.0+ (CTE).
    WITH RECURSIVE usuarios AS (
        SELECT
            CAST(TRIM(SUBSTRING_INDEX(p_user_ids, ',', 1)) AS UNSIGNED) AS id,
            CASE WHEN LOCATE(',', p_user_ids) > 0
                 THEN SUBSTRING(p_user_ids, LOCATE(',', p_user_ids) + 1) ELSE '' END AS resto
        UNION ALL
        SELECT
            CAST(TRIM(SUBSTRING_INDEX(resto, ',', 1)) AS UNSIGNED),
            CASE WHEN LOCATE(',', resto) > 0
                 THEN SUBSTRING(resto, LOCATE(',', resto) + 1) ELSE '' END
        FROM usuarios
        WHERE resto <> ''
    )
    SELECT a.*            -- (mesma projeção do 00; trocar por lista explícita se preciso)
    FROM avel.activities a
    JOIN usuarios u ON u.id = a.user_id
    WHERE a.done_time >= p_from
      AND a.done_time <  p_to + INTERVAL 1 DAY
      AND a.is_deleted = 0
    ORDER BY a.done_time DESC;
END $$

DELIMITER ;

-- Como chamar:
--   -- vários usuários (um dia)
--   CALL avel.sp_activities_por_usuario_periodo('22226784,24390583,16596360', '2026-06-09', '2026-06-09');
--   -- um único usuário
--   CALL avel.sp_activities_por_usuario_periodo('24705122', '2026-06-09', '2026-06-09');
