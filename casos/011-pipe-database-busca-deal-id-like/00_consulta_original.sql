-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- pipe_database — busca "contém" por deal_id, com match exato priorizado.
-- =============================================================

SELECT deal_id, person_name, title, email
          FROM pipe_database
          WHERE CAST(deal_id AS CHAR) LIKE CONCAT('%', 3091, '%')
          ORDER BY
            CASE
              WHEN CAST(deal_id AS CHAR) = CAST(3091 AS CHAR) THEN 0
              ELSE 1
            END,
            deal_id
          LIMIT 10;
