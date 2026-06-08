DELIMITER $$

CREATE PROCEDURE bi.sp_leads_por_contato (
    IN p_phone VARCHAR(120),
    IN p_email VARCHAR(255)
)
BEGIN
    SELECT DISTINCT lead_id FROM (
        SELECT lead_id
        FROM bi.leads_data_connections
        WHERE p_phone MEMBER OF (phones_list)
        UNION
        SELECT lead_id
        FROM bi.leads_emails
        WHERE email = p_email
    ) t;
END $$

DELIMITER ;
