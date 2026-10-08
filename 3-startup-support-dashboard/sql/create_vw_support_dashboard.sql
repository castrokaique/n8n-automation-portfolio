CREATE OR REPLACE VIEW public.vw_support_dashboard AS
SELECT
  -- identifiers
  COALESCE(fc.protocol_number, s.protocol_number) AS protocol_number,
  COALESCE(fc.sleekflow_conversation_id, s.sleekflow_conversation_id) AS sleekflow_conversation_id,

  -- status: closed if it exists in the fact table (closed-only) or the session says so
  CASE WHEN fc.protocol_number IS NOT NULL OR s.status = 'closed' THEN 'Closed' ELSE 'Backlog' END AS conversation_status,
  CASE WHEN fc.protocol_number IS NOT NULL OR s.status = 'closed' THEN 1 ELSE 0 END AS is_closed,
  CASE WHEN fc.protocol_number IS NOT NULL OR s.status = 'closed' THEN 0 ELSE 1 END AS is_backlog,

  -- dates
  (COALESCE(fc.opened_at, s.opened_at) AT TIME ZONE 'America/Sao_Paulo')::date AS reference_date,
  COALESCE(fc.opened_at, s.opened_at) AS opened_at,
  COALESCE(fc.closed_at, s.closed_at) AS closed_at,

  -- context
  ch.channel_name,
  COALESCE(fc.customer_country, s.customer_country) AS customer_country,
  fc.conversation_type,
  ag.agent_name,
  ag.agent_type,

  -- categories
  cat.category_name,
  mc.macro_category_name,

  -- time metrics
  fc.first_response_time_seconds,
  fc.average_response_time_seconds,
  fc.average_handle_time_seconds,
  CASE
    WHEN fc.sla_met IS NULL THEN NULL
    WHEN fc.sla_met THEN 1
    ELSE 0
  END AS sla_met_flag,

  -- csat
  csat.csat_value,
  csat.responded_at AS csat_responded_at,
  dr.reason_name AS detractor_reason,
  csat.detractor_summary

FROM dim_conversation_sessions AS s
FULL OUTER JOIN fact_conversations AS fc
  ON fc.protocol_number = s.protocol_number
LEFT JOIN dim_channels AS ch
  ON ch.channel_id = COALESCE(fc.channel_id, s.channel_id)
LEFT JOIN dim_agents AS ag
  ON ag.agent_id = fc.agent_id
LEFT JOIN dim_categories AS cat
  ON cat.category_id = fc.category_id
LEFT JOIN dim_macro_categories AS mc
  ON mc.macro_category_id = cat.macro_category_id
LEFT JOIN fact_csat_responses AS csat
  ON csat.conversation_id = COALESCE(fc.protocol_number, s.protocol_number)
LEFT JOIN dim_detractor_reasons AS dr
  ON dr.detractor_reason_id = csat.detractor_reason_id;