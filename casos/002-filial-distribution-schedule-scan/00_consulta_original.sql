-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- Tabela: app.filial_distribution_positions (~1,64 milhão de linhas)
-- Objetivo: listar os usuários distintos de um schedule.
-- =============================================================

EXPLAIN ANALYZE
SELECT DISTINCT user_id
FROM app.filial_distribution_positions
WHERE schedule_id = 58387;
