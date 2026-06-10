-- =============================================================
-- Tuning — aplicar e re-rodar o EXPLAIN ANALYZE para comparar.
-- Caso: avel.activities (~4,46M linhas) — atividades do dia por lista de usuários.
-- Baseline: full table scan de 4,46M para reter 317 (~8,86 s a quente).
--
-- A consulta JÁ é sargável (range em done_time, IN em user_id, igualdade em
-- is_deleted) — só falta o índice. NÃO precisa reescrever a consulta.
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 1 (único e prioritário): índice composto (user_id, done_time).
--
-- Por que essa ordem:
--   - user_id PRIMEIRO  -> com IN (42 ids), vira 42 range scans (um por usuário),
--     cada um lendo só as linhas do dia daquele usuário (em vez de varrer 4,46M).
--   - done_time DEPOIS  -> atende o range do dia e entrega cada usuário já ordenado
--     por done_time, então o ORDER BY done_time DESC fica barato (merge/sort de ~317;
--     no caso de 1 só user_id, vira leitura reversa do índice, sem filesort).
-- -------------------------------------------------------------
CREATE INDEX idx_activities_user_donetime
    ON avel.activities (user_id, done_time);


-- -------------------------------------------------------------
-- Variações a considerar (medir antes de decidir):
--   - (user_id, done_time, is_deleted): inclui is_deleted no índice. Só vale se
--     muitos registros desses usuários no dia forem is_deleted=1 (aí filtra no
--     índice em vez de na linha). Em geral is_deleted=0 é a maioria -> ganho mínimo.
--   - (user_id, is_deleted, done_time): igualdade-igualdade-range; pinpoint dos
--     is_deleted=0 antes do range de data. Alternativa se o filtro is_deleted cortar
--     muito. Mantém o ORDER BY com um pequeno sort.
--   - O índice NÃO é covering (a consulta traz 18 colunas) — após o range scan há
--     fetch das ~317 linhas na tabela; barato perto de varrer 4,46M.
-- -------------------------------------------------------------


-- -------------------------------------------------------------
-- ANTES DE APLICAR — checar o que já existe:
-- -------------------------------------------------------------
-- SHOW CREATE TABLE avel.activities;
-- SHOW INDEX  FROM avel.activities;
--   - Se já houver índice começando por user_id, ESTENDER para incluir done_time
--     em vez de criar outro (evita redundância).
--   - Confirmar tipo de done_time e se há FK em user_id (índice de FK por user_id
--     sozinho não basta para o ORDER BY/range — precisa do done_time junto).


-- -------------------------------------------------------------
-- VALIDAÇÃO — re-rodar e comparar (vale para as versões A e B do 00):
--   - esperado: "Index range scan" em idx_activities_user_donetime lendo ~317
--     linhas, SEM "Table scan on activities";
--   - sem filesort (ou um sort minúsculo de 317 linhas);
--   - tempo caindo de ~8,86 s para a casa de ms (ganho vale a frio também).
-- -------------------------------------------------------------
-- EXPLAIN ANALYZE
-- SELECT ... FROM avel.activities
-- WHERE user_id IN (...) AND done_time >= '2026-06-09 00:00:00'
--   AND done_time <= '2026-06-09 23:59:59.999000' AND is_deleted = 0
-- ORDER BY done_time DESC;


-- -------------------------------------------------------------
-- Custo a ponderar:
--   - Índice a mais numa tabela de 4,46M = espaço + custo de escrita. `activities`
--     provavelmente tem escrita frequente (registro de atividades), mas o filtro é
--     extremamente seletivo (~0,007%), então compensa com folga.
-- -------------------------------------------------------------
