-- =============================================================
-- Tuning — aplicar em ordem e re-rodar o EXPLAIN ANALYZE entre os passos.
-- Caso: bi.pack_auc (~2,69M linhas) — maior/último AUC por cliente (spitfire).
-- Baseline: 4 table scans da tabela inteira + subquery dependente; ~11,6 s.
--
-- A reescrita PRESERVA a semântica atual (ethos do repo):
--   assessor/big_team  = registro da ULTIMA DATA do cliente;
--   max_auc            = MAX(auc) de TODO o historico do cliente;
--   data_max_auc       = data em que esse maior AUC ocorreu.
-- (Se a regra de negocio for "foto da ultima data", ver pendencia no README.)
-- =============================================================

-- -------------------------------------------------------------
-- PASSO 0 (BLOQUEADOR): a coluna `data` é TEXT guardando uma data, e a tabela
-- NÃO TEM PRIMARY KEY NEM ÍNDICE ALGUM (confirmado no SHOW CREATE TABLE).
--
-- Confirmado:
--   - `data` = text no formato ISO 'YYYY-MM-DD HH:MM:SS' (ex.: '2020-11-30 00:00:00').
--     Como é ISO zero-padded, MAX(data) lexicográfico bate com o cronológico HOJE,
--     mas é frágil (quebra se entrar outro formato) e não indexa sem prefixo.
--   - `auc` = double  -> MAX(auc) numérico OK, sem bug lexicográfico.
--   - `cliente` = bigint -> ótimo para liderar os índices.
--   - Tabela SEM PK e SEM índices -> por isso TUDO é full scan.
--
-- >>> CAMINHO A — band-aid (destrava já, NÃO mexe no schema): índice de prefixo.
--     OBS: prefixo NÃO habilita o "loose index scan" do MAX (o MySQL não consegue
--     garantir o extremo só pelo prefixo), então o ganho é parcial. Use só se não
--     puder alterar o schema agora.
-- CREATE INDEX idx_pack_auc_cliente_data     ON bi.pack_auc (cliente, `data`(19));
-- CREATE INDEX idx_pack_auc_cliente_auc_data ON bi.pack_auc (cliente, auc, `data`(19));
--
-- >>> CAMINHO B — correto (APLICADO): coluna gerada DATE + índices nela.
--     Não quebra app/ETL (a `data` TEXT continua).
--
-- IMPORTANTE — usar STORED, não VIRTUAL:
--   Índice sobre coluna gerada VIRTUAL pode servir VALOR STALE em leitura
--   100% COVERING (o LATERAL lê só auc+data_d, ambos no índice, sem recalcular).
--   Isso causou data_max_auc = 0000-00-00 na prática. STORED materializa na
--   linha e é imune a esse problema (custo: reescreve a tabela uma vez).
--
-- A expressão é ROBUSTA por garantia (lixo -> NULL), mesmo que a origem aqui
-- seja 100% ISO limpa; STR_TO_DATE('') também devolveria '0000-00-00'.
ALTER TABLE bi.pack_auc
    ADD COLUMN data_d DATE AS (
        CASE
            WHEN `data` IS NULL
              OR `data` = ''
              OR `data` LIKE '0000-00-00%'                       THEN NULL
            ELSE STR_TO_DATE(`data`, '%Y-%m-%d %H:%i:%s')        -- outro formato -> NULL
        END
    ) STORED;
-- Se o sql_mode tiver ALLOW_INVALID_DATES, datas tipo '2020-02-30' podem escapar;
-- nesse caso some um guarda extra: ... < DATE '1000-01-01' THEN NULL.

-- >>> SE VOCÊ JÁ CRIOU como VIRTUAL (resultou em 0000-00-00 via índice stale),
--     migre para STORED assim (dropar índices e coluna, recriar STORED, reindexar):
-- ALTER TABLE bi.pack_auc DROP INDEX idx_pack_auc_cliente_datad,
--                         DROP INDEX idx_pack_auc_cliente_auc_datad;
-- ALTER TABLE bi.pack_auc DROP COLUMN data_d;
-- (re-rodar o ALTER STORED acima e recriar os índices do PASSO 1)

-- (Estrutural, recomendado à parte) a tabela não tem PK. Avaliar adicionar uma
-- chave primária de verdade (coluna natural única ou surrogate), o que beneficia
-- replicação e TODO acesso à tabela — não só esta query:
-- ALTER TABLE bi.pack_auc ADD COLUMN id BIGINT AUTO_INCREMENT PRIMARY KEY FIRST;

-- -------------------------------------------------------------
-- PASSO 1 (prioritário): índices que matam os 4 full scans (sobre data_d).
--
--   idx (cliente, data_d)        -> MAX(data_d) por cliente vira "loose index scan"
--                                   (Using index for group-by): ~96k leituras de
--                                   índice em vez de varrer 2,69M + temporary table.
--   idx (cliente, auc, data_d)   -> maior AUC por cliente + a data desse AUC numa
--                                   única "index dive" por cliente (COVERING):
--                                   mata SCAN #3 (MAX(auc)) E SCAN #4 (subquery).
-- -------------------------------------------------------------
CREATE INDEX idx_pack_auc_cliente_datad
    ON bi.pack_auc (cliente, data_d);

CREATE INDEX idx_pack_auc_cliente_auc_datad
    ON bi.pack_auc (cliente, auc, data_d);

-- (Opcional) cobrir também assessor/big_team do registro da última data, para o
-- JOIN do `latest` não precisar voltar à tabela. big_team é TEXT (prefixo):
-- CREATE INDEX idx_pack_auc_cliente_datad_cover
--     ON bi.pack_auc (cliente, data_d, big_team(20), assessor(40));


-- -------------------------------------------------------------
-- PASSO 2: reescrita — 1 passada por cliente, sem dupla agregação
--          e sem subquery correlacionada na projeção.
--
--   - `ld`     : MAX(data) por cliente -> loose index scan em (cliente, data).
--   - `latest` : pega o registro daquela última data e filtra spitfire ANTES de
--                buscar o AUC (reduz o LATERAL a ~milhares de clientes, não 96k).
--   - LATERAL  : por cliente spitfire, 1 index dive em (cliente, auc, data) traz
--                o maior AUC e a data dele -> substitui SCAN #3 + SCAN #4.
--   - Requer MySQL 8.0.14+ (JOIN LATERAL). Alternativa sem LATERAL abaixo.
-- -------------------------------------------------------------
WITH ld AS (
    SELECT cliente, MAX(data_d) AS max_data
    FROM bi.pack_auc
    WHERE cliente IS NOT NULL
    GROUP BY cliente
),
latest AS (
    SELECT p.assessor, p.cliente, p.big_team
    FROM ld
    JOIN bi.pack_auc p
      ON p.cliente = ld.cliente
     AND p.data_d  = ld.max_data
    WHERE p.big_team = 'spitfire'
)
SELECT
    l.assessor,
    l.cliente,
    l.big_team,
    REPLACE(CAST(mx.max_auc AS CHAR), '.', ',') AS max_auc,
    mx.data_d AS data_max_auc
FROM latest l
JOIN LATERAL (
    SELECT p2.auc AS max_auc, p2.data_d
    FROM bi.pack_auc p2
    WHERE p2.cliente = l.cliente
    ORDER BY p2.auc DESC, p2.data_d ASC    -- desempate: data MAIS ANTIGA, para reproduzir
                                           -- o que a original (LIMIT 1 sem ORDER BY) devolve.
                                           -- Trocar para DESC se a regra desejada for "mais recente".
    LIMIT 1
) mx ON TRUE
ORDER BY l.cliente
LIMIT 1000;

-- NOTA (fidelidade): se um cliente tiver mais de um registro na MESMA última data
-- (time sempre 00:00:00 favorece empate), o JOIN do `latest` pode devolver >1 linha
-- por cliente — exatamente como no original. Se quiser 1 linha por cliente, decidir
-- o critério de desempate do assessor (ex.: ROW_NUMBER no `latest`).


-- -------------------------------------------------------------
-- PASSO 2 (alternativa sem LATERAL): join com derived agregado por (cliente),
-- usando o índice (cliente, auc, data) para o MAX(auc) e a data via ANY_VALUE/
-- correlação leve. Útil se a versão do MySQL for < 8.0.14.
-- (Materializa o maior-AUC só para os clientes spitfire é melhor; medir.)
-- -------------------------------------------------------------


-- -------------------------------------------------------------
-- ANTES DE APLICAR — checar o que já existe:
-- -------------------------------------------------------------
-- SHOW CREATE TABLE bi.pack_auc;
-- SHOW INDEX  FROM bi.pack_auc;
--   - Confirmar PK e se já há índice por (cliente, ...) para estender em vez de duplicar.
--   - Confirmar tipos de `data` (DATE/DATETIME) e `auc` (decimal?).


-- -------------------------------------------------------------
-- VALIDAÇÃO — re-rodar EXPLAIN ANALYZE e conferir:
--   - "Using index for group-by" no MAX(data) (sem temporary table);
--   - index lookup/range em (cliente, auc, data) no LATERAL (sem table scan);
--   - sumiço dos 4 table scans de 2,69M linhas;
--   - tempo caindo de ~11,6 s para a casa de dezenas de ms.
-- -------------------------------------------------------------


-- -------------------------------------------------------------
-- Custo a ponderar:
--   - Dois índices novos numa tabela de 2,69M = espaço + custo de escrita. Como
--     `pack_auc` parece ser tabela de BI (carga em lote, leitura pesada), tende a
--     compensar com folga. Confirmar a frequência de escrita.
-- -------------------------------------------------------------
