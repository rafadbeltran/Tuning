-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- Tabela notifications usa colunas geradas (VIRTUAL) que
-- processam JSON em tempo de leitura.
-- =============================================================

SELECT
    nn.id,
    n.status_id_virt     AS statusId,
    n.deadline_time_virt AS time_limit,
    n.schedule_id_virt   AS schedule_meetings_id,
    nn.notification_id
FROM intranet.notification_notifiers AS nn
JOIN intranet.notifications AS n ON n.id = nn.notification_id
WHERE n.type = 3
  AND n.status_id_virt = 0          -- BUG: compara varchar com inteiro (ver diagnóstico)
  AND n.schedule_id_virt != 43
  AND nn.user_id NOT IN (
      SELECT id FROM intranet.users_usuario
      WHERE role_id IN (142, 165, 174) AND is_active = 1
  );
--Ver com renato | Lucas