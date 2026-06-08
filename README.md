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
