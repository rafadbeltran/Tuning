-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- "Custódia do cliente" — agregação por cliente com GROUP_CONCAT + vários
-- JSON_OBJECT/JSON_EXTRACT, juntando tabelas a..h.
-- ATENÇÃO: query colada TRUNCADA (termina no meio do JSON_OBJECT de previdencia).
--          Faltam: FROM/JOINs (aliases a,c,d,e,f,g,h), WHERE, GROUP BY. Completar.
-- =============================================================

SELECT
            CAST(CONCAT('[', GROUP_CONCAT(DISTINCT a.cliente ORDER BY a.net_em_m DESC), ']') AS JSON) AS customerCodes,
            SUM(a.net_em_m) AS customerCustody,
            SUM(a.net_internacional) as internationalCustomerCustody,
            IFNULL(CAST(CONCAT('[', GROUP_CONCAT(c.deal_id), ']') AS JSON), JSON_ARRAY()) AS dealIds,
            coalesce(d.name,'-') AS customerName,
            convert(d.cpf_cnpj, CHAR) as cpf_cnpj,
            CASE WHEN d.pj = 1 THEN 'PJ' ELSE 'PF' END AS customerNature,
            d.customer_profile AS customerProfile,
            CASE
                WHEN JSON_VALID(f.linked_accounts) AND JSON_TYPE(f.linked_accounts) = 'ARRAY'
                THEN f.linked_accounts
                ELSE JSON_ARRAY() END AS linkedAccounts,
            CASE
                WHEN SUM(f.account_type = 'main') > 0 THEN 'main'
                WHEN SUM(f.account_type = 'dependent') > 0 THEN 'dependent'
                ELSE null END AS accountType,
            min(d.entry_date) as entryDate,
            CASE
                WHEN COALESCE(d.sow, 0) > 1 AND d.customer_profile IS NOT NULL AND f.account_type IS NOT NULL AND g.id is not null THEN convert(1,float)
                WHEN COALESCE(d.sow, 0) = 1 AND d.customer_profile IS NOT NULL AND f.account_type IS NOT NULL THEN convert(1,float)
                ELSE convert(0,float) END AS isMapped,
            SUM(COALESCE(d.sow, 0)) AS sow,
            CASE
                WHEN SUM(e.ambos = 1) > 0 THEN 'Ambos'
                WHEN SUM(e.confirmacao = 1) > 0 THEN 'Externo'
                WHEN SUM(e.consentimento = 1) > 0 THEN 'Interno'
                ELSE 'Sem OpenInvestment' END AS statusOpenInvestment,
            MAX(e.data_permissao) AS dateOpenInvestment,
            f.customer_id AS customerId,
            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.renda_fixa, '$.interest')) AS JSON),
                'requested',   CAST(MAX(JSON_EXTRACT(h.renda_fixa, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.renda_fixa, '$.introduced')) AS JSON)
            ) AS renda_fixa,

            JSON_OBJECT(
            'interest',   CAST(MAX(JSON_EXTRACT(h.renda_variavel, '$.interest')) AS JSON),
            'requested',  CAST(MAX(JSON_EXTRACT(h.renda_variavel, '$.requested')) AS JSON),
            'introduced', CAST(MAX(JSON_EXTRACT(h.renda_variavel, '$.introduced')) AS JSON)
            ) AS renda_variavel,

            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.seguros, '$.interest')) AS JSON),
                'requested',  CAST(MAX(JSON_EXTRACT(h.seguros, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.seguros, '$.introduced')) AS JSON)
            ) AS seguros,

            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.internacional, '$.interest')) AS JSON),
                'requested',  CAST(MAX(JSON_EXTRACT(h.internacional, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.internacional, '$.introduced')) AS JSON)
            ) AS internacional,

            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.consorcio, '$.interest')) AS JSON),
                'requested',  CAST(MAX(JSON_EXTRACT(h.consorcio, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.consorcio, '$.introduced')) AS JSON)
            ) AS consorcio,

            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.mesa_trader, '$.interest')) AS JSON),
                'requested',  CAST(MAX(JSON_EXTRACT(h.mesa_trader, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.mesa_trader, '$.introduced')) AS JSON)
            ) AS mesa_trader,

            JSON_OBJECT(
                'interest',   CAST(MAX(JSON_EXTRACT(h.previdencia, '$.interest')) AS JSON),
                'requested',  CAST(MAX(JSON_EXTRACT(h.previdencia, '$.requested')) AS JSON),
                'introduced', CAST(MAX(JSON_EXTRACT(h.previdencia, '$.introduced')) A
                -- << TRUNCADO no original; completar JSON_OBJECTs restantes + FROM/JOINs/WHERE/GROUP BY
