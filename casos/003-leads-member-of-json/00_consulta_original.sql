-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- Tabela: bi.leads_data_connections (~3,84 milhões de linhas)
-- Objetivo: achar lead_id(s) que tenham um telefone OU um e-mail
-- específico, guardados em colunas JSON (arrays).
-- =============================================================

EXPLAIN ANALYZE
SELECT DISTINCT lead_id
FROM bi.leads_data_connections
WHERE "5584486420"                MEMBER OF (phones_list)
   OR "fabricio_ruschel@hotmail.com" MEMBER OF (emails_list);
