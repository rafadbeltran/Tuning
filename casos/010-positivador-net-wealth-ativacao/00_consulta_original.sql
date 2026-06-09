-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- avel.positivador — net por customer + último wealth_range + última ativação.
-- ATENÇÃO: query colada TRUNCADA (termina no LEFT JOIN customers). Completar.
-- =============================================================

WITH p_agg AS (
        SELECT
            customer_id,
            user_id,
            SUM(net_em_m) AS net,
            JSON_ARRAYAGG(cliente) AS accounts
        FROM avel.positivador
        WHERE customer_id IS NOT NULL
            AND user_id = 1591
        GROUP BY customer_id
        ),
        w_latest AS (
        SELECT customer_id, wealth_range
        FROM (
            SELECT
            w.*,
            ROW_NUMBER() OVER (PARTITION BY w.customer_id ORDER BY w.date DESC) AS rn
            FROM avel.customer_wealth_range_in_month w
        ) t
        WHERE t.rn = 1
        ),
        ar_latest AS (
        SELECT client, MAX(date) AS date
        FROM bi.activation_records
        WHERE activation = 1
        GROUP BY client
        )
        SELECT
        p.customer_id,
        c.name,
        w.wealth_range,
        MAX(ar.date) AS activation_date,
        p.net,
        p.accounts
        FROM p_agg p
        LEFT JOIN avel.customers c ON c.id = p.customer_id
        -- << TRUNCADO no original; faltam os JOINs com w_latest / ar_latest, GROUP BY, etc.
