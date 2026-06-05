-- =============================================================
-- Procedure parametrizada da consulta tunada (caso 001)
-- Mesma consulta do 02_tuning.sql (Passo 1), com os literais
-- trocados por parâmetros.
--
-- ATENÇÃO (o ponto central deste caso):
--   p_status_id é VARCHAR de propósito, NÃO INT.
--   status_id_virt é varchar(50). Se o parâmetro for INT, a
--   comparação `status_id_virt = p_status_id` volta a coagir a
--   coluna para número e DERRUBA o uso de idx_notif_otimizacao —
--   regredindo para a varredura de ~657 mil linhas. Mantendo o
--   parâmetro VARCHAR, a comparação fica string-com-string e o
--   índice continua sendo usado (plano validado em 01_diagnostico.md).
--   Idealmente o parâmetro deve ter o mesmo charset/collation da
--   coluna, para não introduzir uma conversão implícita que também
--   inviabilizaria o índice.
-- =============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS intranet.sp_notificacoes_pendentes $$

CREATE PROCEDURE intranet.sp_notificacoes_pendentes (
    IN p_type              INT,           -- n.type             (ex.: 3)
    IN p_status_id         VARCHAR(50),   -- n.status_id_virt   (ex.: '0')  <- VARCHAR!
    IN p_schedule_excluido INT,           -- n.schedule_id_virt a excluir (ex.: 43)
    IN p_roles_excluidas   VARCHAR(255)   -- lista CSV de role_id (ex.: '142,165,174')
)
BEGIN
    SELECT
        nn.id,
        n.status_id_virt     AS statusId,
        n.deadline_time_virt AS time_limit,
        n.schedule_id_virt   AS schedule_meetings_id,
        nn.notification_id
    FROM intranet.notification_notifiers AS nn
    JOIN intranet.notifications AS n ON n.id = nn.notification_id
    WHERE n.type = p_type
      AND n.status_id_virt = p_status_id          -- string = string (índice preservado)
      AND n.schedule_id_virt <> p_schedule_excluido
      AND nn.user_id NOT IN (
          SELECT id FROM intranet.users_usuario
          WHERE FIND_IN_SET(role_id, p_roles_excluidas)  -- substitui role_id IN (...)
            AND is_active = 1
      );
END $$

DELIMITER ;

-- -------------------------------------------------------------
-- Chamada equivalente à consulta original:
-- -------------------------------------------------------------
-- CALL intranet.sp_notificacoes_pendentes(3, '0', 43, '142,165,174');

-- -------------------------------------------------------------
-- Notas
-- -------------------------------------------------------------
-- 1. FIND_IN_SET não usa índice em role_id, mas aqui é irrelevante:
--    o filtro de roles roda sobre o usuário já localizado por PK
--    (single-row lookup no antijoin), não sobre uma varredura.
-- 2. Se preferir evitar FIND_IN_SET por completo, dá para montar a
--    lista via SQL dinâmico (PREPARE/EXECUTE) injetando p_roles_excluidas
--    direto no IN (...). Custa mais complexidade e exige sanitizar a
--    entrada; para esta carga não compensa.
-- 3. p_type e p_schedule_excluido são INT porque type e schedule_id_virt
--    são tratados numericamente (o range em schedule_id_virt usa índice
--    normalmente — só status_id_virt tinha o problema de coerção).
