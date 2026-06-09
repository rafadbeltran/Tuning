-- =============================================================
-- Tuning — aplicar em ordem e re-rodar o EXPLAIN ANALYZE entre os passos.
-- Caso: count(deal_id) por user_id num dia, com LIKE em updated_time.
-- Baseline: index scan de ~359k linhas para reter 141 (~621 ms).
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 1 (prioritário): tornar o predicado SARGÁVEL.
--
-- Trocar o LIKE de prefixo por um range half-open [dia, dia+1):
--   - Para de converter updated_time -> string a cada linha.
--   - Permite que o otimizador use um range de índice na coluna.
--   - half-open (< dia seguinte) é mais robusto que BETWEEN ... '23:59:59.999':
--     funciona com qualquer precisão de fração de segundo (DATETIME(0/3/6))
--     e não corre o risco de perder linhas na borda do dia.
-- -------------------------------------------------------------
SELECT COUNT(deal_id) AS qtd, user_id
FROM avel.score_assigned_leads
WHERE updated_time >= '2026-06-05 00:00:00'
  AND updated_time <  '2026-06-06 00:00:00'
GROUP BY user_id;


-- -------------------------------------------------------------
-- PASSO 2: índice covering (updated_time, user_id, deal_id).
--
-- Por que essa ordem:
--   - updated_time PRIMEIRO -> o range do PASSO 1 vira range scan e lê só
--     ~141 linhas em vez de ~359 mil. ESTE é o ganho dominante.
--   - user_id + deal_id DEPOIS -> deixa o índice COVERING (a consulta só usa
--     essas 3 colunas), então não há lookup na tabela.
--   - O GROUP BY user_id ganha um pequeno filesort (~141 linhas) porque a
--     liderança é updated_time, não user_id — custo desprezível perto de
--     deixar de ler as ~359 mil linhas.
-- -------------------------------------------------------------
CREATE INDEX idx_sal_updated_user_deal
    ON avel.score_assigned_leads (updated_time, user_id, deal_id);

-- Nota: se deal_id for NOT NULL, COUNT(deal_id) = COUNT(*); aí dá para usar
-- só (updated_time, user_id) e trocar a consulta por COUNT(*). O deal_id no
-- índice só serve para cobrir o COUNT(deal_id) quando há NULLs.


-- -------------------------------------------------------------
-- ANTES DE APLICAR — checar o que já existe:
-- -------------------------------------------------------------
-- SHOW CREATE TABLE avel.score_assigned_leads;
-- SHOW INDEX  FROM avel.score_assigned_leads;
--
--   a) FK_score (FK de user_id): NÃO remover — é necessário para a foreign key.
--      O índice novo é complementar (atende o range por data).
--   b) Se já existir índice começando por updated_time, ESTENDA-O para incluir
--      (user_id, deal_id) em vez de criar outro (evita índice redundante).
--   c) Confirmar o tipo de updated_time (DATETIME vs TIMESTAMP) e a precisão.


-- -------------------------------------------------------------
-- VALIDAÇÃO — re-rodar e comparar.
-- Esperado: range scan / covering em idx_sal_updated_user_deal lendo ~141 linhas,
-- estimativa (rows) batendo com o real, e tempo caindo de ~621 ms para sub-ms.
-- -------------------------------------------------------------
-- EXPLAIN ANALYZE
-- SELECT COUNT(deal_id) AS qtd, user_id
-- FROM avel.score_assigned_leads
-- WHERE updated_time >= '2026-06-05 00:00:00'
--   AND updated_time <  '2026-06-06 00:00:00'
-- GROUP BY user_id;


-- -------------------------------------------------------------
-- Custo a ponderar (não bloqueia):
--   - Índice a mais = custo em INSERT/UPDATE e disco. Como `score_assigned_leads`
--     parece ter escrita frequente (scoring de leads), vale confirmar o volume de
--     escrita; mas o filtro por dia é muito seletivo (~0,04%), então compensa.
-- -------------------------------------------------------------
