-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- Leituras de tabela inteira sem filtro (full scan).
-- =============================================================

-- (A) avel.pipe_database — projeção sem WHERE
select deal_id, status, owner_name, user_id, stage_id from avel.pipe_database;

-- (B) avel.customer_info — SELECT * sem WHERE
select * from avel.customer_info;
