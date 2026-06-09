# Tuning

Coleção versionada dos meus casos de tuning — consultas SQL, índices e outras
otimizações. Cada caso fica numa pasta própria em [`casos/`](casos/), com o
baseline, o diagnóstico e as correções, de modo que dê para acompanhar o
raciocínio e reproduzir o antes/depois.

## Casos

| # | Caso | Tecnologia | Status |
|---|------|-----------|--------|
| 001 | [Consulta de notificações — coerção em `status_id_virt`](casos/001-notifications-status-id/) | MySQL / InnoDB | 🟢 Resolvido |
| 002 | [`SELECT DISTINCT user_id` por `schedule_id` — full scan](casos/002-filial-distribution-schedule-scan/) | MySQL / InnoDB | 🟢 Resolvido |
| 003 | [`MEMBER OF` em colunas JSON — índice multi-valor](casos/003-leads-member-of-json/) | MySQL / InnoDB | 🟢 Resolvido |
| 004 | [Tempo operacional médio do SDR — regra Node → stored procedure](casos/004-tempo-operacional-medio-sdr/) | MySQL / InnoDB | 🟡 Em andamento |
| 005 | [Leituras de tabela inteira sem filtro (`pipe_database`, `customer_info`)](casos/005-full-reads-sem-filtro/) | MySQL / InnoDB | ⚪ Backlog |
| 006 | [`score_assigned_leads` — `updated_time LIKE` em coluna de data](casos/006-score-assigned-leads-like-data/) | MySQL / InnoDB | 🟢 Resolvido |
| 007 | [`bi.pack_auc` — maior/último AUC por cliente (`big_team`)](casos/007-pack-auc-ultimo-maior-auc/) | MySQL / InnoDB | 🟢 Resolvido |
| 008 | [`intranet.customer` — won/lost por lista de assessores na janela do mês](casos/008-customer-won-lost-by-assessores/) | MySQL / InnoDB | ⚪ Backlog |
| 009 | [`avel.activities` — atividades do dia por lista de usuários](casos/009-activities-user-done-time-dia/) | MySQL / InnoDB | ⚪ Backlog |
| 010 | [`avel.positivador` — net + último wealth + última ativação](casos/010-positivador-net-wealth-ativacao/) | MySQL / InnoDB | ⚪ Backlog |
| 011 | [`pipe_database` — busca de `deal_id` com `CAST` + `LIKE '%n%'`](casos/011-pipe-database-busca-deal-id-like/) | MySQL / InnoDB | ⚪ Backlog |
| 012 | [Custódia do cliente — agregação JSON gigante](casos/012-customer-custody-agregacao-json/) | MySQL / InnoDB | ⚪ Backlog |

> Status: 🟡 em andamento · 🟢 resolvido · ⚪ ideia/backlog

## Como cada caso é organizado

Cada pasta em `casos/NNN-descricao-curta/` segue o mesmo esqueleto:

- `README.md` — contexto, status e resumo do caso.
- `00_consulta_original.sql` — baseline, antes de qualquer mudança.
- `01_diagnostico.md` — leitura do `EXPLAIN` (ou profiling) e a causa raiz.
- `02_tuning.sql` — correções, em ordem de aplicação.

Arquivos extras (`03_*`, prints, dumps de `SHOW CREATE TABLE` etc.) entram na
pasta do caso conforme a necessidade.

## Criando um caso novo

Copie [`_template/`](_template/) para `casos/NNN-descricao-curta/`, preencha os
arquivos e adicione uma linha na tabela acima.
