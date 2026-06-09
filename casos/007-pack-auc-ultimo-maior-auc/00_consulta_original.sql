-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- bi.pack_auc — maior AUC por cliente + data do registro, time = 'spitfire'.
-- Duas versões coladas (iterações do mesmo problema).
-- =============================================================

-- (A) Versão original — VEIO TRUNCADA no GROUP BY (completar).
--     Usa subquery correlacionada para data_max_auc + self-join pela última data.
SELECT
    t.assessor,
    t.cliente,
    t.big_team,
    REPLACE(CAST(MAX(t.auc) AS CHAR), '.', ',') AS max_auc,
    (
        SELECT data
        FROM bi.pack_auc p2
        WHERE p2.cliente = t.cliente
        ORDER BY p2.auc DESC
        LIMIT 1
    ) AS data_max_auc
FROM bi.pack_auc t
INNER JOIN (
    SELECT cliente, MAX(data) AS max_data
    FROM bi.pack_auc
    GROUP BY cliente
) latest ON t.cliente = latest.cliente AND t.data = latest.max_data
WHERE t.big_team = 'spitfire'
GROUP BY t.assessor, t.cliente, t.big_team
ORDER BY t.cliente;

-- (B) Reescrita posterior — separa "última data" de "maior AUC" em dois derived tables.
SELECT
    s.assessor,
    s.cliente,
    s.big_team,
    REPLACE(CAST(m.max_auc AS CHAR), '.', ',') AS max_auc,
    (
        SELECT data FROM bi.pack_auc
        WHERE cliente = s.cliente AND auc = m.max_auc
        LIMIT 1
    ) AS data_max_auc
FROM (
    SELECT p.assessor, p.cliente, p.big_team
    FROM bi.pack_auc p
    INNER JOIN (
        SELECT cliente, MAX(data) AS max_data
        FROM bi.pack_auc
        GROUP BY cliente
    ) ld ON p.cliente = ld.cliente AND p.data = ld.max_data
    WHERE p.big_team = 'spitfire'
) s
INNER JOIN (
    SELECT cliente, MAX(auc) AS max_auc
    FROM bi.pack_auc
    GROUP BY cliente
) m ON s.cliente = m.cliente
ORDER BY s.cliente
LIMIT 1000;
