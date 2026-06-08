-- =============================================================
-- Tuning — aplicar e re-rodar o EXPLAIN ANALYZE para comparar.
-- Caso: SELECT DISTINCT user_id ... WHERE schedule_id = ?
-- sobre app.filial_distribution_positions (~1,64 milhão de linhas).
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 1 (prioritário): índice composto covering (schedule_id, user_id).
--
-- Por que composto e nessa ordem:
--   - schedule_id PRIMEIRO  -> troca o full scan por um range scan,
--     lendo só as ~1.591 linhas do schedule (em vez de 1,64M).
--   - user_id   DEPOIS      -> torna o índice COVERING (a consulta só
--     precisa dessas duas colunas) e, por vir ordenado, permite
--     resolver o DISTINCT pelo próprio índice, eliminando a
--     "Temporary table with deduplication".
-- -------------------------------------------------------------
CREATE INDEX idx_fdp_schedule_user
    ON app.filial_distribution_positions (schedule_id, user_id);


-- -------------------------------------------------------------
-- ANTES DE APLICAR — checar o que já existe:
-- -------------------------------------------------------------
-- SHOW CREATE TABLE app.filial_distribution_positions;
-- SHOW INDEX  FROM app.filial_distribution_positions;
--
--   a) Se já houver um índice começando por schedule_id, ESTENDA-O
--      para incluir user_id em vez de criar um novo (evita duplicar).
--   b) Se user_id já fizer parte da PRIMARY KEY, um índice só em
--      (schedule_id) já é covering no InnoDB (a PK vem nas folhas) —
--      o segundo membro do índice acima seria redundante.


-- -------------------------------------------------------------
-- VALIDAÇÃO — re-rodar e comparar (esperado: range scan ~1.591 linhas,
-- sem temporary table, e ganho mesmo na execução fria).
-- -------------------------------------------------------------
-- EXPLAIN ANALYZE
-- SELECT DISTINCT user_id
-- FROM app.filial_distribution_positions
-- WHERE schedule_id = 58387;


-- -------------------------------------------------------------
-- Custo a ponderar (não é bloqueador, só consciência):
--   - Índice a mais = custo em INSERT/UPDATE e disco. A tabela é
--     grande e parece ter escrita frequente (distribuição de filiais),
--     mas o filtro é muito seletivo (~0,1%), então tende a compensar.
-- -------------------------------------------------------------
