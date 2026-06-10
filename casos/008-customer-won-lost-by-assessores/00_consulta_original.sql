-- =============================================================
-- Consulta original (baseline) — antes do tuning
-- intranet.customer — deals ganhos/perdidos por uma lista de assessores
-- dentro de uma janela de data (junho/2026), status won/lost.
--
-- Formatada para leitura (mesma semântica do original gerado pela GUI).
-- O gargalo provável está no WHERE: OR entre won_by_id/lost_by_id E OR entre
-- as janelas won_date/lost_date.
-- =============================================================

SELECT
    `intranet`.`customer`.`id`,
    `intranet`.`customer`.`deal_id`,
    `intranet`.`customer`.`origin_id`,
    `intranet`.`customer`.`name`,
    `intranet`.`customer`.`phone`,
    `intranet`.`customer`.`email`,
    `intranet`.`customer`.`campaing`,
    `intranet`.`customer`.`creation_date`,
    `intranet`.`customer`.`won_date`,
    `intranet`.`customer`.`lost_date`,
    `intranet`.`customer`.`person_type_id`,
    `intranet`.`customer`.`state`,
    `intranet`.`customer`.`city`,
    `intranet`.`customer`.`created_by_id`,
    `intranet`.`customer`.`value`,
    `intranet`.`customer`.`owner_name_to_id`,
    `intranet`.`customer`.`owner_id`,
    `intranet`.`customer`.`stage_id`,
    `intranet`.`customer`.`lost_reason`,
    `intranet`.`customer`.`platform`,
    `intranet`.`customer`.`status`,
    `intranet`.`customer`.`notes_count`,
    `intranet`.`customer`.`corretora_banco`,
    `intranet`.`customer`.`profissao`,
    `intranet`.`customer`.`turno_contato`,
    `intranet`.`customer`.`faixa_patrimonio`,
    `intranet`.`customer`.`mautic_id`,
    `intranet`.`customer`.`won_by_id`,
    `intranet`.`customer`.`lost_by_id`,
    `intranet`.`customer`.`pj`,
    `intranet`.`customer`.`pf`,
    `intranet`.`customer`.`caixa`,
    `intranet`.`customer`.`schedule_date`,
    `intranet`.`customer`.`publico`,
    `intranet`.`customer`.`id_beeviral`,
    `intranet`.`customer`.`observacoes`,
    `intranet`.`customer`.`solded_at`,
    `intranet`.`customer`.`influencer`,
    `intranet`.`customer`.`cpf_cnpj`,
    `intranet`.`customer`.`turno`,
    `intranet`.`customer`.`faturamento`,
    `intranet`.`customer`.`caixa_balance`,
    `intranet`.`customer`.`redventure_id`,
    `intranet`.`customer`.`source_url`,
    `intranet`.`customer`.`fbp`,
    `intranet`.`customer`.`useragent`,
    `intranet`.`customer`.`fbc`,
    `intranet`.`customer`.`pipedrive_id`,
    `intranet`.`customer`.`interest`,
    `intranet`.`customer`.`flow_name`,
    `intranet`.`customer`.`meeting_schedule_date`,
    `intranet`.`customer`.`won_type_selected`,
    `intranet`.`customer`.`income_range`,
    `intranet`.`customer`.`intranet_deal_id`,
    `intranet`.`customer`.`scheduled_by_id`,
    `intranet`.`customer`.`sprinter_scheduled_date`,
    `intranet`.`customer`.`meta_leadgen_id`,
    `intranet`.`customer`.`meta_page_id`
FROM `intranet`.`customer`
WHERE (
            `intranet`.`customer`.`won_by_id`  IN ('3646','3398','3623','3487','3642','3635','3641','3408','3478','3472','3402','3624','3144','3399','3490','3409','3477','3480','3638','3400','3640','3140','3245','3485','3626','3115','3403','3475','3411','3637','3474','3633','2860','3420','3622','3631','3421','3422','3644','3489','3482','3415','3401','3484','3639','3473','3645','3423','3240','3476','3424','3634','3625','3486','3643','3425')
         OR `intranet`.`customer`.`lost_by_id` IN ('3646','3398','3623','3487','3642','3635','3641','3408','3478','3472','3402','3624','3144','3399','3490','3409','3477','3480','3638','3400','3640','3140','3245','3485','3626','3115','3403','3475','3411','3637','3474','3633','2860','3420','3622','3631','3421','3422','3644','3489','3482','3415','3401','3484','3639','3473','3645','3423','3240','3476','3424','3634','3625','3486','3643','3425')
      )
  AND (
            (`intranet`.`customer`.`lost_date` >= '2026-06-01 00:00:00' AND `intranet`.`customer`.`lost_date` <= '2026-06-30 23:59:59.999000')
         OR (`intranet`.`customer`.`won_date`  >= '2026-06-01 00:00:00' AND `intranet`.`customer`.`won_date`  <= '2026-06-30 23:59:59.999000')
      )
  AND `intranet`.`customer`.`status` IN ('won','lost');
