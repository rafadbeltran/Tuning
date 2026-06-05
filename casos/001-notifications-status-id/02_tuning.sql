-- =============================================================
-- Tuning — aplicar em ordem e re-rodar EXPLAIN entre os passos
-- =============================================================
-- RESULTADO: o PASSO 1 sozinho resolveu (~657 mil linhas -> 6, ~4,53 ms).
-- O índice idx_notif_otimizacao já era equivalente, então os PASSOS 2 e 3
-- ficaram DISPENSADOS. Mantidos abaixo apenas como referência.
-- Ver 01_diagnostico.md para o EXPLAIN ANALYZE antes/depois.
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 1 (prioritário): corrigir a comparação de tipo.
-- Sozinho isso pode fazer o otimizador voltar a usar um índice
-- já existente, possivelmente sem precisar criar nada novo.
-- -------------------------------------------------------------

-- Opção A — mudar só o literal para string (menos invasivo):
SELECT
    nn.id,
    n.status_id_virt     AS statusId,
    n.deadline_time_virt AS time_limit,
    n.schedule_id_virt   AS schedule_meetings_id,
    nn.notification_id
FROM intranet.notification_notifiers AS nn
JOIN intranet.notifications AS n ON n.id = nn.notification_id
WHERE n.type = 3
  AND n.status_id_virt = '0'       -- string, não 0
  AND n.schedule_id_virt <> 43
  AND nn.user_id NOT IN (
      SELECT id FROM intranet.users_usuario
      WHERE role_id IN (142, 165, 174) AND is_active = 1
  );

-- Opção B (preferível se statusId é sempre numérico no app):
-- redefinir a coluna como INT, eliminando a pegadinha de vez.
-- ALTER TABLE intranet.notifications
--   DROP COLUMN status_id_virt,
--   ADD COLUMN status_id_virt INT
--     AS (json_unquote(json_extract(`details`, '$.statusId')));
-- (atenção: recriar índices que referenciem a coluna)


-- -------------------------------------------------------------
-- PASSO 2 (DISPENSADO): índice composto (equality primeiro, range depois).
-- Colunas VIRTUAL são indexáveis no InnoDB — não precisa STORED.
-- NÃO foi necessário: o EXPLAIN ANALYZE mostrou que idx_notif_otimizacao
-- já cobre o caso. Criar este índice seria duplicação. Mantido comentado.
-- -------------------------------------------------------------
-- CREATE INDEX idx_notif_tuning
--     ON intranet.notifications (type, status_id_virt, schedule_id_virt);


-- -------------------------------------------------------------
-- PASSO 3 (opcional): índice de cobertura, se a consulta for muito
-- quente. Inclui deadline_time_virt para evitar acesso à tabela.
-- Custo: mais manutenção em escrita (str_to_date).
-- -------------------------------------------------------------
-- CREATE INDEX idx_notif_tuning_cover
--     ON intranet.notifications (type, status_id_virt, schedule_id_virt, deadline_time_virt);


-- -------------------------------------------------------------
-- Refinamento opcional: NOT EXISTS no lugar do NOT IN
-- (mais à prova de NULL; não é o gargalo atual).
-- -------------------------------------------------------------
-- ... AND NOT EXISTS (
--     SELECT 1 FROM intranet.users_usuario u
--     WHERE u.id = nn.user_id
--       AND u.role_id IN (142, 165, 174)
--       AND u.is_active = 1
-- )
