DELIMITER $$

CREATE PROCEDURE app.sp_usuarios_distintos_por_schedule (
    IN p_schedule_id INT
)
BEGIN
    SELECT DISTINCT user_id
    FROM app.filial_distribution_positions
    WHERE schedule_id = p_schedule_id;
END $$

DELIMITER ;
