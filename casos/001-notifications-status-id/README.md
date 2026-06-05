# 001 — Consulta de notificações (MySQL / InnoDB)

**Status:** 🟢 Resolvido — o Passo 1 (corrigir `= 0` → `= '0'`) destravou o índice
`idx_notif_otimizacao` e derrubou de ~657 mil linhas varridas para 6 linhas lidas
(~4,53 ms no `EXPLAIN ANALYZE`). Não foi preciso criar índice novo.

Tuning de uma consulta sobre `intranet.notifications`, cuja tabela usa colunas
geradas (VIRTUAL) que processam JSON (`details`) em tempo de leitura.

## Arquivos

- [`00_consulta_original.sql`](00_consulta_original.sql) — baseline antes do tuning.
- [`01_diagnostico.md`](01_diagnostico.md) — leitura do EXPLAIN e causa raiz.
- [`02_tuning.sql`](02_tuning.sql) — correções em ordem de aplicação (em validação).

## Resumo do diagnóstico

O principal problema é a comparação `status_id_virt = 0`: a coluna é `varchar(50)`
comparada com um inteiro, o que força coerção numérica de toda a coluna e impede
o uso de índice — levando a varredura de ~657 mil linhas.

## Ordem de ataque

1. Corrigir a comparação (`= '0'` ou redefinir a coluna como `INT`) e re-rodar o EXPLAIN.
2. Se necessário, criar o índice composto `(type, status_id_virt, schedule_id_virt)`.
3. Opcional: índice de cobertura incluindo `deadline_time_virt`.

## Pendências

- [x] Validar o EXPLAIN após o Passo 1 (mudança do literal para `'0'`).
- [x] Conferir se `idx_notif_otimizacao` já dava conta — dava; Passo 2/3 dispensados.
- [x] Medir antes/depois e registrar os números (ver [01_diagnostico.md](01_diagnostico.md)).
- [ ] Decidir se mantém a Opção A (literal `'0'`) ou parte para a Opção B (coluna `INT`)
      como blindagem definitiva contra a coerção de tipo.
- [ ] Rodar uma vez com dados em que se espera retorno, para validar a lógica (o teste
      atual deu `rows=0`).
