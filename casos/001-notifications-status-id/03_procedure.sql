DELIMITER $$

CREATE PROCEDURE intranet.sp_notificacoes_pendentes (
    IN p_type              INT,
    IN p_status_id         VARCHAR(50),
    IN p_schedule_excluido INT,
    IN p_roles_excluidas   VARCHAR(255)
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
      AND n.status_id_virt = p_status_id
      AND n.schedule_id_virt <> p_schedule_excluido
      AND nn.user_id NOT IN (
          SELECT id FROM intranet.users_usuario
          WHERE FIND_IN_SET(role_id, p_roles_excluidas)
            AND is_active = 1
      );
END $$

DELIMITER ;
