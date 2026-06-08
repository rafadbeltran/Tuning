-- =============================================================
-- Tuning — caso 003
-- Consulta: lead_id por um telefone OU um e-mail guardados em colunas
-- JSON (phones_list, emails_list) de bi.leads_data_connections (~3,84M).
-- Pré-requisito: MySQL 8.0.17+ (índice multi-valor).
--
-- Resumo da solução (o que de fato foi feito):
--   PASSO 1 — telefone: índice multi-valor idx_ldc_phones (resolveu).
--   PASSO 2 — e-mail: o MV index NÃO constrói (dado super-mesclado);
--             solução = tabela de lookup normalizada + sync assíncrona
--             (outbox + EVENT + interruptor).
--   PASSO 3 — consulta reescrita com UNION (cada ramo usa seu índice).
-- =============================================================


-- =============================================================
-- PASSO 1 (telefone): índice multi-valor sobre phones_list
-- =============================================================
-- MEMBER OF / JSON_CONTAINS / JSON_OVERLAPS conseguem usar índice
-- multi-valor. Os valores são string (o literal vem entre aspas), por
-- isso CAST para CHAR(N) ARRAY. Um MV index admite só UMA coluna JSON.
--
-- O N precisa caber o maior valor do array, SENÃO o CREATE aborta:
--   [22001][3907] Data too long for functional index 'idx_ldc_phones'.
-- Medir antes:
--   SELECT MAX(CHAR_LENGTH(jt.v))
--   FROM bi.leads_data_connections,
--        JSON_TABLE(phones_list, '$[*]' COLUMNS (v VARCHAR(255) PATH '$')) jt;
-- Máximo medido: 108 (suspeito — telefone não tem 108 chars; provável
-- lixo no array, não afeta a busca). CHAR(120) dá folga.
-- Teto do InnoDB: chave <= 3072 bytes; com utf8mb4, CHAR vai até ~767.
CREATE INDEX idx_ldc_phones
    ON bi.leads_data_connections ( (CAST(phones_list AS CHAR(120) ARRAY)) );


-- =============================================================
-- PASSO 2 (e-mail): tabela de lookup + sincronização assíncrona
-- =============================================================
-- Por que NÃO um MV index em emails_list:
--   o mesmo CREATE falha com
--     [HY000][3906] Exceeded max total length of values per record
--     for multi-valued index ... by 511 bytes.
--   Causa: ~324 leads carregam um blob super-mesclado de 241 e-mails
--   DISTINTOS e reais (bug de resolução de identidade), cuja soma por
--   registro estoura o limite do MV index. Não é duplicação -> reduzir
--   o CHAR não ajuda (CHAR(255) e CHAR(120) deram o MESMO estouro: o
--   teto só corta valores acima dele, e o maior e-mail real é 99).
--   Diagnóstico das linhas gordas:
--     SELECT lead_id, JSON_LENGTH(emails_list) qtd,
--            JSON_STORAGE_SIZE(emails_list) bytes
--     FROM bi.leads_data_connections ORDER BY bytes DESC LIMIT 10;
--
-- Solução: tabela de lookup normalizada (índice B-tree comum, imune ao
-- limite do MV index), mantida por outbox + EVENT (custo O(1) no caminho
-- de escrita — adequado a volume alto de inserts).

-- ---- 2.1) Tabelas ----
-- Lookup: 1 linha por (email, conexão). PK (email, conn_id) -> busca por
-- email; KEY(conn_id) -> manutenção. conn_id = leads_data_connections.id
-- (NÃO lead_id: pode haver várias conexões por lead; manter pela PK da
-- origem evita apagar dados de linhas irmãs).
CREATE TABLE bi.leads_emails (
    email   VARCHAR(255) NOT NULL,
    conn_id INT          NOT NULL,
    lead_id INT          NOT NULL,
    PRIMARY KEY (email, conn_id),
    KEY idx_le_conn (conn_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Fila (outbox): só guarda quais conexões mudaram. PK dá dedup natural.
CREATE TABLE bi.leads_emails_queue (
    conn_id INT NOT NULL,
    PRIMARY KEY (conn_id)
) ENGINE=InnoDB;

-- Interruptor (kill switch): liga/desliga a sincronização sem DDL.
-- MySQL NÃO tem DISABLE TRIGGER — sem este flag, "parar" o trigger
-- exigiria DROP (metadata lock + perda da definição). Com o flag,
-- pausar/religar é um UPDATE numa tabela de 1 linha (barato, fica em cache).
CREATE TABLE bi.sync_control (
    nome  VARCHAR(50) NOT NULL PRIMARY KEY,
    ativo TINYINT     NOT NULL DEFAULT 1
) ENGINE=InnoDB;
INSERT INTO bi.sync_control (nome, ativo) VALUES ('leads_emails', 1);

-- ---- 2.2) Backfill inicial (uma vez) ----
-- Triggers só pegam o que muda dali pra frente; o estado atual entra aqui.
INSERT IGNORE INTO bi.leads_emails (email, conn_id, lead_id)
SELECT jt.v, c.id, c.lead_id
FROM bi.leads_data_connections c
JOIN JSON_TABLE(c.emails_list, '$[*]' COLUMNS (v VARCHAR(255) PATH '$')) jt;

-- ---- 2.3) Triggers O(1): NÃO explodem JSON; só enfileiram o id ----
-- O worker faz o trabalho pesado em lote. Cada trigger checa o
-- interruptor bi.sync_control antes de enfileirar.
DELIMITER $$

CREATE TRIGGER trg_ldc_emails_ai
AFTER INSERT ON bi.leads_data_connections
FOR EACH ROW
BEGIN
    IF (SELECT ativo FROM bi.sync_control WHERE nome = 'leads_emails') = 1 THEN
        INSERT IGNORE INTO bi.leads_emails_queue (conn_id) VALUES (NEW.id);
    END IF;
END $$

CREATE TRIGGER trg_ldc_emails_au
AFTER UPDATE ON bi.leads_data_connections
FOR EACH ROW
BEGIN
    -- só enfileira se a sincronização está ligada E o que afeta a lookup mudou
    IF (SELECT ativo FROM bi.sync_control WHERE nome = 'leads_emails') = 1
       AND (NOT (NEW.emails_list <=> OLD.emails_list) OR NEW.lead_id <> OLD.lead_id) THEN
        INSERT IGNORE INTO bi.leads_emails_queue (conn_id) VALUES (NEW.id);
    END IF;
END $$

CREATE TRIGGER trg_ldc_emails_ad
AFTER DELETE ON bi.leads_data_connections
FOR EACH ROW
BEGIN
    IF (SELECT ativo FROM bi.sync_control WHERE nome = 'leads_emails') = 1 THEN
        INSERT IGNORE INTO bi.leads_emails_queue (conn_id) VALUES (OLD.id);
    END IF;
END $$

DELIMITER ;

-- ---- 2.4) Worker assíncrono: processa a fila em lote a cada 30s ----
-- Claim por snapshot (tabela temporária) -> mudanças que chegam DURANTE
-- a execução ficam pro próximo ciclo. Para cada conn_id: apaga o estado
-- antigo e reexplode do estado atual. Registro deletado -> o JOIN com a
-- origem não acha nada -> some da lookup (correto), sem lógica extra.
SET GLOBAL event_scheduler = ON;   -- persistir também no my.cnf: event_scheduler=ON

DELIMITER $$

CREATE EVENT ev_sync_leads_emails
ON SCHEDULE EVERY 30 SECOND
DO
sync_body: BEGIN
    -- respeita o mesmo interruptor: se desligado, não processa neste ciclo
    IF (SELECT ativo FROM bi.sync_control WHERE nome = 'leads_emails') <> 1 THEN
        LEAVE sync_body;   -- LEAVE exige bloco rotulado
    END IF;

    DROP TEMPORARY TABLE IF EXISTS _le_batch;
    CREATE TEMPORARY TABLE _le_batch (conn_id INT PRIMARY KEY);

    -- snapshot do que será processado neste ciclo
    INSERT INTO _le_batch (conn_id)
    SELECT conn_id FROM bi.leads_emails_queue;

    -- apaga o estado antigo das conexões do lote
    -- (WHERE explícito por conn_id: usa o índice e evita o alerta de
    --  "DELETE sem WHERE" do modo safe-updates)
    DELETE FROM bi.leads_emails
    WHERE conn_id IN (SELECT conn_id FROM _le_batch);

    -- reexplode a partir do estado atual da origem (insert/update)
    INSERT IGNORE INTO bi.leads_emails (email, conn_id, lead_id)
    SELECT jt.v, c.id, c.lead_id
    FROM bi.leads_data_connections c
    JOIN _le_batch b ON b.conn_id = c.id,
         JSON_TABLE(c.emails_list, '$[*]' COLUMNS (v VARCHAR(255) PATH '$')) jt;

    -- limpa SÓ os ids processados (preserva o que chegou durante o ciclo)
    DELETE FROM bi.leads_emails_queue
    WHERE conn_id IN (SELECT conn_id FROM _le_batch);

    DROP TEMPORARY TABLE IF EXISTS _le_batch;
END $$

DELIMITER ;


-- =============================================================
-- PASSO 3: consulta reescrita — UNION, NÃO OR
-- =============================================================
-- Com OR o otimizador não combina o MEMBER OF (MV index) com a lookup
-- -> volta ao full scan dos 3,84M (~14 s). Com UNION cada ramo usa o seu
-- índice isoladamente. A leads_emails já guarda lead_id, então o ramo de
-- e-mail nem toca na tabela grande. (Versão parametrizada em 03_procedure.sql.)
-- EXPLAIN ANALYZE
SELECT DISTINCT lead_id FROM (
    SELECT lead_id
    FROM bi.leads_data_connections
    WHERE "5584486420" MEMBER OF (phones_list)        -- usa idx_ldc_phones

    UNION

    SELECT lead_id
    FROM bi.leads_emails
    WHERE email = "fabricio_ruschel@hotmail.com"        -- usa PK (email, conn_id)
) t;
-- Resultado: ~8.956 ms (original) -> ~0,08 ms (ver 01_diagnostico.md).


-- =============================================================
-- PAUSAR / RELIGAR (kill switch)
-- =============================================================
-- Os 3 triggers E o EVENT respeitam o flag bi.sync_control.
--   -- pausar (triggers param de enfileirar; event não processa):
--   UPDATE bi.sync_control SET ativo = 0 WHERE nome = 'leads_emails';
--   -- religar:
--   UPDATE bi.sync_control SET ativo = 1 WHERE nome = 'leads_emails';
-- IMPORTANTE: enquanto pausado, mudanças NÃO são capturadas. Ao religar,
-- rodar a RECONCILIAÇÃO completa (nota (b)) para cobrir o intervalo.
--
-- Alternativas:
--   ALTER EVENT bi.ev_sync_leads_emails DISABLE;   -- pausa só o worker (... ENABLE)
--   SET GLOBAL event_scheduler = OFF;              -- desliga TODOS os events
--   SHOW CREATE TRIGGER bi.trg_ldc_emails_ai;      -- salvar antes de dropar
--   DROP TRIGGER IF EXISTS bi.trg_ldc_emails_ai;   -- idem _au, _ad (precisa metadata lock)
--
-- Listar / inspecionar os events:
--   SHOW EVENTS FROM bi;
--   SELECT EVENT_NAME, STATUS, INTERVAL_VALUE, INTERVAL_FIELD, LAST_EXECUTED
--     FROM information_schema.EVENTS WHERE EVENT_SCHEMA = 'bi';
--   SHOW VARIABLES LIKE 'event_scheduler';         -- precisa estar ON


-- =============================================================
-- NOTAS DE OPERAÇÃO
-- =============================================================
-- a) Frescor: lookup defasada no máximo ~30s (ajustar o EVERY).
--
-- b) Reconciliação completa (blinda a janela de corrida do worker e o
--    caso de TRUNCATE/bulk load na origem, que não disparam trigger):
--      TRUNCATE bi.leads_emails;
--      INSERT IGNORE INTO bi.leads_emails (email, conn_id, lead_id)
--      SELECT jt.v, c.id, c.lead_id
--      FROM bi.leads_data_connections c
--      JOIN JSON_TABLE(c.emails_list,'$[*]' COLUMNS (v VARCHAR(255) PATH '$')) jt;
--
-- c) Collation: email usa utf8mb4_0900_ai_ci. Conferir se bate com a
--    comparação na origem (JSON) para não divergir / inibir o índice.
--
-- d) Verificação de consistência (deve dar 0 divergências):
--      SELECT COUNT(*) FROM (
--        SELECT c.id, jt.v
--        FROM bi.leads_data_connections c
--        JOIN JSON_TABLE(c.emails_list,'$[*]' COLUMNS (v VARCHAR(255) PATH '$')) jt
--        WHERE NOT EXISTS (SELECT 1 FROM bi.leads_emails le
--                          WHERE le.conn_id = c.id AND le.email = jt.v)
--      ) d;
-- =============================================================
