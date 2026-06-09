-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- avel.score_assigned_leads — contagem de leads por usuário num dia.
-- Filtro por LIKE sobre a coluna de data/hora.
-- =============================================================

select count(deal_id) as qtd, user_id from avel.score_assigned_leads
where updated_time like '2026-06-05%' group by user_id;
