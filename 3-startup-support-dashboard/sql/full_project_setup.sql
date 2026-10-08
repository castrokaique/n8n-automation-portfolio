-- =============================================================================
-- full_project_setup.sql
-- Support KPI dashboard - master setup script (Supabase / PostgreSQL)
--
-- Builds the complete database for a new project:
--   Section 1  Dimension tables
--   Section 2  Fact tables
--   Section 3  Row Level Security (enabled on every table, no policies)
--   Section 4  Reference data (macro categories, detractor reasons, targets,
--              example category taxonomy)
--   Section 5  Reporting view  public.vw_support_dashboard
--   Section 6  OPTIONAL demo data (fictitious and deterministic)
--
-- HOW TO RUN
--   * Use it on an EMPTY project. Running it twice fails because the objects
--     already exist.
--   * Real client: run sections 1-5 only. In the Supabase SQL Editor, select
--     the text from the top of this file down to the line
--     "END OF SECTION 5" and click Run (the editor runs the selected text).
--   * Demo / portfolio: run the whole file (sections 1-6).
--   * Sections 1-5 run inside one transaction (all or nothing).
--     Section 6 runs inside its own transaction.
--
-- BEFORE GOING LIVE WITH A NEW CLIENT
--   * Section 4 ships an EXAMPLE category taxonomy (a WhatsApp / AI platform
--     support operation). Review it and replace it with the client's own
--     categories before the classification pipeline goes live.
--   * Section 5 converts dates to the America/Sao_Paulo time zone
--     (reference_date). Change it if the client operates in another time zone.
--
-- NOTES
--   * Timestamps are stored in UTC (timestamptz). fact_conversations.
--     conversation_date is the UTC date of opened_at.
--   * Message text is NOT stored (privacy): only metadata.
--   * fact_messages.protocol_number has no foreign key on purpose.
-- =============================================================================


BEGIN;

-- =============================================================================
-- SECTION 1 - DIMENSION TABLES
-- =============================================================================

CREATE TABLE public.dim_agents (
  agent_id    text PRIMARY KEY,
  agent_name  text NOT NULL,
  agent_type  text NOT NULL CHECK (agent_type IN ('human', 'ai')),
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.dim_macro_categories (
  macro_category_id    serial PRIMARY KEY,
  macro_category_name  text NOT NULL UNIQUE,
  macro_description    text,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.dim_categories (
  category_id           serial PRIMARY KEY,
  category_name         text NOT NULL UNIQUE,
  created_at            timestamptz NOT NULL DEFAULT now(),
  category_description  text,
  macro_category_id     integer REFERENCES public.dim_macro_categories (macro_category_id)
);

CREATE TABLE public.dim_channels (
  channel_id    text PRIMARY KEY,
  channel_name  text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Control table: solves the reuse of the same conversation id by the channel
-- provider (one conversation id can map to several protocols).
CREATE TABLE public.dim_conversation_sessions (
  protocol_number            text PRIMARY KEY,
  sleekflow_conversation_id  text NOT NULL,
  status                     text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  opened_at                  timestamptz NOT NULL DEFAULT now(),
  closed_at                  timestamptz,
  channel_id                 text,
  customer_country           text
);

CREATE TABLE public.dim_detractor_reasons (
  detractor_reason_id  serial PRIMARY KEY,
  reason_name          text NOT NULL UNIQUE,
  reason_description   text,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.dim_targets (
  target_id          serial PRIMARY KEY,
  kpi_name           text NOT NULL CHECK (kpi_name IN ('sla', 'csat')),
  region             text NOT NULL DEFAULT 'global',
  target_value       numeric(5,2) NOT NULL,
  is_active          boolean NOT NULL DEFAULT true,
  effective_from     date NOT NULL DEFAULT CURRENT_DATE,
  created_at         timestamptz NOT NULL DEFAULT now(),
  threshold_seconds  integer
);


-- =============================================================================
-- SECTION 2 - FACT TABLES
-- =============================================================================

-- One row per CLOSED conversation.
CREATE TABLE public.fact_conversations (
  protocol_number                text PRIMARY KEY,
  channel_id                     text NOT NULL REFERENCES public.dim_channels (channel_id),
  category_id                    integer REFERENCES public.dim_categories (category_id),
  agent_id                       text NOT NULL REFERENCES public.dim_agents (agent_id),
  opened_at                      timestamptz NOT NULL,
  closed_at                      timestamptz NOT NULL,
  conversation_date              date NOT NULL,
  conversation_type              text NOT NULL CHECK (conversation_type IN ('ai', 'human', 'mixed')),
  customer_country               text,
  first_response_time_seconds    integer NOT NULL,
  average_response_time_seconds  numeric(10,2) NOT NULL,
  average_handle_time_seconds    integer NOT NULL,
  sla_met                        boolean NOT NULL,
  created_at                     timestamptz NOT NULL DEFAULT now(),
  sleekflow_conversation_id      text
);

-- At most one CSAT response per conversation (enforced by the pipeline).
CREATE TABLE public.fact_csat_responses (
  csat_response_id     serial PRIMARY KEY,
  conversation_id      text NOT NULL REFERENCES public.fact_conversations (protocol_number),
  csat_value           text NOT NULL CHECK (csat_value IN ('satisfied', 'neutral', 'unsatisfied')),
  responded_at         timestamptz NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  detractor_reason_id  integer REFERENCES public.dim_detractor_reasons (detractor_reason_id),
  detractor_summary    text
);

CREATE TABLE public.fact_messages (
  message_id                 text PRIMARY KEY,
  protocol_number            text NOT NULL,   -- no foreign key on purpose
  agent_id                   text REFERENCES public.dim_agents (agent_id),
  sender_type                text NOT NULL CHECK (sender_type IN ('customer', 'human', 'ai')),
  sent_at                    timestamptz NOT NULL,
  message_order              integer,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  sleekflow_conversation_id  text
);


-- =============================================================================
-- SECTION 3 - ROW LEVEL SECURITY
-- Enabled on every table, with no policies: the public API gets no access;
-- the service role and the table owner keep full access.
-- =============================================================================

ALTER TABLE public.dim_agents              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_macro_categories    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_categories          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_channels            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_conversation_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_detractor_reasons   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dim_targets             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fact_conversations      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fact_csat_responses     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fact_messages           ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- SECTION 4 - REFERENCE DATA
-- =============================================================================

-- 4.1 Macro categories (ids 1-7 on a fresh database)
INSERT INTO public.dim_macro_categories (macro_category_name, macro_description) VALUES
  ('Bugs',          'Plataforma não funcionando como deveria'),
  ('Automation',    'Configuração de agentes de IA e criação/ajuste de fluxos'),
  ('Product',       'Dúvidas de uso de funcionalidades existentes'),
  ('Account',       'Cobrança, faturas, plano, assinatura'),
  ('Onboarding',    'Configuração inicial, verificação de número, migração'),
  ('Policy',        'Políticas do WhatsApp/Meta, LGPD e afins'),
  ('Uncategorized', 'Categoria ainda não classificada em uma macro categoria específica (fallback)');

-- 4.2 Detractor reasons (ids 1-6 on a fresh database)
INSERT INTO public.dim_detractor_reasons (reason_name, reason_description) VALUES
  ('Response Time / Delay',             'Cliente reclamou da demora na resposta ou resolução'),
  ('Issue Not Resolved',                'Problema do cliente não foi de fato resolvido'),
  ('Agent Tone / Empathy',              'Cliente percebeu falta de empatia ou tom inadequado no atendimento'),
  ('Product Limitation',                'Insatisfação causada por limitação real do produto, não por erro do atendimento'),
  ('Repetitive / Had to Explain Again', 'Cliente precisou repetir informações ou explicar o problema mais de uma vez'),
  ('Other',                             'Motivo não se encaixa nas categorias acima');

-- 4.3 KPI targets (effective_from defaults to today's date)
INSERT INTO public.dim_targets (kpi_name, region, target_value, threshold_seconds) VALUES
  ('sla',  'global', 80, 600),   -- 80% of first responses within 600 seconds
  ('csat', 'global', 85, NULL);  -- 85% satisfied

-- 4.4 EXAMPLE category taxonomy (WhatsApp / AI platform support operation).
-- REVIEW AND REPLACE these rows with the client's own categories before the
-- classification pipeline goes live. "Outros" is the fallback category and
-- should stay. New categories are added with plain INSERTs.
INSERT INTO public.dim_categories (category_name, category_description, macro_category_id)
SELECT v.category_name, v.category_description, m.macro_category_id
FROM (VALUES
  ( 1, 'Message Delivery Failure',           'Cliente relata que mensagens não estão chegando ou sendo entregues',                                               'Bugs'),
  ( 2, 'App Crash or Freeze',                'Plataforma trava ou fecha inesperadamente',                                                                        'Bugs'),
  ( 3, 'Integration Sync Error',             'Erro de sincronização com CRM, Supabase ou outras integrações',                                                    'Bugs'),
  ( 4, 'Flow Builder Configuration Issue',   'Dificuldade ao configurar ou publicar um fluxo',                                                                   'Automation'),
  ( 5, 'AI Agent Unexpected Behavior',       'Agente de IA responde de forma inesperada ou incorreta',                                                           'Automation'),
  ( 6, 'AI Training / Knowledge Base Setup', 'Dúvidas sobre como treinar o agente ou configurar base de conhecimento',                                            'Automation'),
  ( 7, 'How to Use Broadcast Feature',       'Dúvida sobre como usar envio em massa',                                                                            'Product'),
  ( 8, 'Template Message Best Practices',    'Dúvidas gerais sobre como criar templates eficazes',                                                               'Product'),
  ( 9, 'Reporting and Analytics Questions',  'Dúvida sobre como interpretar relatórios da plataforma',                                                           'Product'),
  (10, 'Invoice or Payment Issue',           'Problema com fatura, pagamento não reconhecido ou cobrança indevida',                                              'Account'),
  (11, 'Plan Upgrade or Downgrade Request',  'Cliente quer mudar de plano',                                                                                      'Account'),
  (12, 'WhatsApp Number Verification',       'Dificuldade para verificar número no WhatsApp Business',                                                           'Onboarding'),
  (13, 'Migration from Another Provider',    'Cliente migrando de outro provedor de WhatsApp API',                                                               'Onboarding'),
  (14, 'WhatsApp Template Rejection',        'Template de mensagem reprovado pela Meta',                                                                         'Policy'),
  (15, 'Data Privacy / LGPD Request',        'Solicitação relacionada a privacidade de dados ou LGPD',                                                           'Policy'),
  (16, 'Outros',                             'Categoria de fallback: usar quando a conversa não se encaixa claramente em nenhuma categoria específica disponível', 'Uncategorized')
) AS v(ord, category_name, category_description, macro_name)
JOIN public.dim_macro_categories AS m ON m.macro_category_name = v.macro_name
ORDER BY v.ord;


-- =============================================================================
-- SECTION 5 - REPORTING VIEW
-- Single data source for the dashboard (one row per protocol).
--
-- Rules:
--   * The base is the FULL OUTER JOIN of the session control table and the
--     closed-conversation fact table, so no conversation is left out.
--   * A conversation is 'Closed' when it exists in fact_conversations (which
--     only holds closed conversations) or when its session says 'closed';
--     otherwise it is 'Backlog'.
--   * reference_date is the opened_at date in the America/Sao_Paulo time zone.
--   * Percentages (SLA %, CSAT %) are calculated in the BI tool, not here:
--       SLA % = SUM(sla_met_flag) / COUNT(sla_met_flag)
-- =============================================================================

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

FROM public.dim_conversation_sessions AS s
FULL OUTER JOIN public.fact_conversations AS fc
  ON fc.protocol_number = s.protocol_number
LEFT JOIN public.dim_channels AS ch
  ON ch.channel_id = COALESCE(fc.channel_id, s.channel_id)
LEFT JOIN public.dim_agents AS ag
  ON ag.agent_id = fc.agent_id
LEFT JOIN public.dim_categories AS cat
  ON cat.category_id = fc.category_id
LEFT JOIN public.dim_macro_categories AS mc
  ON mc.macro_category_id = cat.macro_category_id
LEFT JOIN public.fact_csat_responses AS csat
  ON csat.conversation_id = COALESCE(fc.protocol_number, s.protocol_number)
LEFT JOIN public.dim_detractor_reasons AS dr
  ON dr.detractor_reason_id = csat.detractor_reason_id;

COMMIT;

-- Quick check for sections 1-5 (found should match expected)
SELECT check_name, found, expected
FROM (
  SELECT 1 AS ord, 'tables created' AS check_name,
         (SELECT COUNT(*) FROM information_schema.tables
           WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
             AND table_name IN ('dim_agents', 'dim_macro_categories', 'dim_categories',
                                'dim_channels', 'dim_conversation_sessions',
                                'dim_detractor_reasons', 'dim_targets',
                                'fact_conversations', 'fact_csat_responses', 'fact_messages')) AS found,
         10 AS expected
  UNION ALL
  SELECT 2, 'view created',
         (SELECT COUNT(*) FROM information_schema.views
           WHERE table_schema = 'public' AND table_name = 'vw_support_dashboard'), 1
  UNION ALL
  SELECT 3, 'macro categories', (SELECT COUNT(*) FROM public.dim_macro_categories), 7
  UNION ALL
  SELECT 4, 'detractor reasons', (SELECT COUNT(*) FROM public.dim_detractor_reasons), 6
  UNION ALL
  SELECT 5, 'targets', (SELECT COUNT(*) FROM public.dim_targets), 2
  UNION ALL
  SELECT 6, 'example categories', (SELECT COUNT(*) FROM public.dim_categories), 16
  UNION ALL
  SELECT 7, 'categories without macro category', (SELECT COUNT(*) FROM public.dim_categories WHERE macro_category_id IS NULL), 0
) AS c
ORDER BY ord;

-- =============================== END OF SECTION 5 ===============================


-- =============================================================================
-- SECTION 6 - OPTIONAL DEMO DATA (fictitious)
-- Needs sections 1-5. Deterministic: the same data every time it runs.
--   12 agents (10 human, 2 AI), 1 channel
--   636 conversations between 2026-06-22 and 2026-08-31:
--     590 closed (session + fact) and 46 in backlog (session only)
--   messages for every conversation, and CSAT for about 27% of closed ones
-- All relations are consistent: every fact has a session, every CSAT points to
-- an existing fact, every message belongs to an existing protocol.
-- =============================================================================

BEGIN;

-- Deterministic pseudo-random number in [0, 1) derived from a text seed.
CREATE FUNCTION pg_temp.demo_rand(seed text) RETURNS double precision
LANGUAGE sql IMMUTABLE AS $$
  SELECT (('x' || substr(md5(seed), 1, 8))::bit(32)::bigint)::double precision / 4294967296.0
$$;

-- 6.1 Agents and channel
INSERT INTO public.dim_agents (agent_id, agent_name, agent_type) VALUES
  ('agent_01', 'Ana Souza',        'human'),
  ('agent_02', 'Bruno Lima',       'human'),
  ('agent_03', 'Carla Mendes',     'human'),
  ('agent_04', 'Diego Alves',      'human'),
  ('agent_05', 'Elisa Rocha',      'human'),
  ('agent_06', 'Felipe Costa',     'human'),
  ('agent_07', 'Gabriela Nunes',   'human'),
  ('agent_08', 'Henrique Dias',    'human'),
  ('agent_09', 'Isabela Martins',  'human'),
  ('agent_10', 'Rafael Pereira',   'human'),
  ('ai_01',    'AI Assistant (Tier 1)',  'ai'),
  ('ai_02',    'AI Assistant (Billing)', 'ai');

INSERT INTO public.dim_channels (channel_id, channel_name) VALUES
  ('whatsapp_demo_01', 'WhatsApp Support Line');

-- 6.2 Staging: weights for categories and countries
CREATE TEMP TABLE demo_category_weights ON COMMIT DROP AS
SELECT w.category_name, w.weight,
       SUM(w.weight) OVER (ORDER BY w.ord) - w.weight AS lo,
       SUM(w.weight) OVER (ORDER BY w.ord)            AS hi
FROM (VALUES
  ( 1, 'Invoice or Payment Issue',           11),
  ( 2, 'Integration Sync Error',             10),
  ( 3, 'How to Use Broadcast Feature',        9),
  ( 4, 'AI Agent Unexpected Behavior',        8),
  ( 5, 'App Crash or Freeze',                 7),
  ( 6, 'Data Privacy / LGPD Request',         7),
  ( 7, 'Reporting and Analytics Questions',   7),
  ( 8, 'Message Delivery Failure',            6),
  ( 9, 'Template Message Best Practices',     6),
  (10, 'Migration from Another Provider',     6),
  (11, 'WhatsApp Number Verification',        6),
  (12, 'AI Training / Knowledge Base Setup',  5),
  (13, 'WhatsApp Template Rejection',         5),
  (14, 'Plan Upgrade or Downgrade Request',   5),
  (15, 'Flow Builder Configuration Issue',    5),
  (16, 'Outros',                              2)
) AS w(ord, category_name, weight);

CREATE TEMP TABLE demo_country_weights ON COMMIT DROP AS
SELECT w.country_code, w.weight,
       SUM(w.weight) OVER (ORDER BY w.ord) - w.weight AS lo,
       SUM(w.weight) OVER (ORDER BY w.ord)            AS hi
FROM (VALUES
  (1, 'BR', 55),
  (2, 'MX', 15),
  (3, 'CO',  8),
  (4, 'AR',  7),
  (5, 'CL',  6),
  (6, 'PE',  5),
  (7, 'US',  4)
) AS w(ord, country_code, weight);

-- 6.3 Staging: one row per conversation (i = 1..590 closed, 591..636 backlog)
CREATE TEMP TABLE demo_conv ON COMMIT DROP AS
WITH rnd AS (
  SELECT
    i,
    (i > 590) AS is_backlog,
    pg_temp.demo_rand(i::text || ':day')   AS r_day,
    pg_temp.demo_rand(i::text || ':hour')  AS r_hour,
    pg_temp.demo_rand(i::text || ':min')   AS r_min,
    pg_temp.demo_rand(i::text || ':sec')   AS r_sec,
    pg_temp.demo_rand(i::text || ':type')  AS r_type,
    pg_temp.demo_rand(i::text || ':agent') AS r_agent,
    pg_temp.demo_rand(i::text || ':cat')   AS r_cat,
    pg_temp.demo_rand(i::text || ':ctry')  AS r_ctry,
    pg_temp.demo_rand(i::text || ':f1')    AS r_f1,
    pg_temp.demo_rand(i::text || ':f2')    AS r_f2,
    pg_temp.demo_rand(i::text || ':aht')   AS r_aht,
    pg_temp.demo_rand(i::text || ':art')   AS r_art
  FROM generate_series(1, 636) AS i
),
typed AS (
  SELECT r.*,
    CASE WHEN r.r_type < 0.55 THEN 'ai'
         WHEN r.r_type < 0.82 THEN 'mixed'
         ELSE 'human' END AS conv_type,
    ( ( DATE '2026-06-22'
        + CASE WHEN r.is_backlog THEN 61 + floor(r.r_day * 10)::int
               ELSE floor(r.r_day * 71)::int END )
      + make_interval(hours => 11 + floor(r.r_hour * 13)::int,
                      mins  => floor(r.r_min * 60)::int,
                      secs  => floor(r.r_sec * 60)::int)
    ) AT TIME ZONE 'UTC' AS opened_at
  FROM rnd AS r
),
picked AS (
  SELECT t.*,
    CASE WHEN t.conv_type = 'ai'
         THEN CASE WHEN t.r_agent < 0.6 THEN 'ai_01' ELSE 'ai_02' END
         ELSE 'agent_' || lpad((1 + floor(t.r_agent * 10)::int)::text, 2, '0')
    END AS agent_id,
    cw.category_name,
    cc.country_code AS customer_country
  FROM typed AS t
  JOIN demo_category_weights AS cw
    ON t.r_cat * (SELECT SUM(weight) FROM demo_category_weights) >= cw.lo
   AND t.r_cat * (SELECT SUM(weight) FROM demo_category_weights) <  cw.hi
  JOIN demo_country_weights AS cc
    ON t.r_ctry * (SELECT SUM(weight) FROM demo_country_weights) >= cc.lo
   AND t.r_ctry * (SELECT SUM(weight) FROM demo_country_weights) <  cc.hi
),
timing AS (
  SELECT p.*,
    -- first response time in seconds (AI is fast; human is slower)
    CASE WHEN p.conv_type = 'human'
         THEN CASE WHEN p.r_f1 < 0.5 THEN 60 + floor(p.r_f2 * 530)::int
                   ELSE 610 + floor(p.r_f2 * 1790)::int END
         ELSE CASE WHEN p.r_f1 < 0.94 THEN 3 + floor(p.r_f2 * 40)::int
                   ELSE 610 + floor(p.r_f2 * 290)::int END
    END AS frt
  FROM picked AS p
),
handled AS (
  SELECT tm.*,
    -- handle time in seconds, always at least 180 s longer than the first response
    GREATEST(240 + floor(power(tm.r_aht, 2) * 5400)::int, tm.frt + 180) AS aht
  FROM timing AS tm
)
SELECT
  h.i,
  h.is_backlog,
  to_char(h.opened_at AT TIME ZONE 'UTC', 'YYYYMMDD-HH24MISS') || '-' || substr(md5(h.i::text || ':p'), 1, 8) AS protocol_number,
  md5(CASE WHEN h.i % 20 = 0 THEN (h.i - 1)::text ELSE h.i::text END || ':c') AS sleekflow_conversation_id,
  h.conv_type,
  h.agent_id,
  h.category_name,
  h.customer_country,
  h.opened_at,
  CASE WHEN h.is_backlog THEN NULL ELSE h.opened_at + make_interval(secs => h.aht) END AS closed_at,
  h.frt,
  h.aht,
  LEAST(round((h.frt * (0.8 + 1.6 * h.r_art) + 15)::numeric, 2), h.aht::numeric) AS art,
  (h.frt <= 600) AS sla_met
FROM handled AS h;

-- 6.4 Sessions (closed and open)
INSERT INTO public.dim_conversation_sessions
  (protocol_number, sleekflow_conversation_id, status, opened_at, closed_at, channel_id, customer_country)
SELECT c.protocol_number, c.sleekflow_conversation_id,
       CASE WHEN c.is_backlog THEN 'open' ELSE 'closed' END,
       c.opened_at, c.closed_at, 'whatsapp_demo_01', c.customer_country
FROM demo_conv AS c
ORDER BY c.i;

-- 6.5 Closed conversations (fact)
INSERT INTO public.fact_conversations
  (protocol_number, channel_id, category_id, agent_id, opened_at, closed_at, conversation_date,
   conversation_type, customer_country, first_response_time_seconds, average_response_time_seconds,
   average_handle_time_seconds, sla_met, created_at, sleekflow_conversation_id)
SELECT c.protocol_number, 'whatsapp_demo_01', cat.category_id, c.agent_id, c.opened_at, c.closed_at,
       (c.opened_at AT TIME ZONE 'UTC')::date,
       c.conv_type, c.customer_country, c.frt, c.art, c.aht, c.sla_met,
       c.closed_at + interval '30 seconds', c.sleekflow_conversation_id
FROM demo_conv AS c
JOIN public.dim_categories AS cat ON cat.category_name = c.category_name
WHERE NOT c.is_backlog
ORDER BY c.i;

-- 6.6 Messages (metadata only)
-- Closed conversations alternate customer / responder messages: the first
-- reply happens at the first response time and the last message at the close.
INSERT INTO public.fact_messages
  (message_id, protocol_number, agent_id, sender_type, sent_at, created_at, sleekflow_conversation_id)
SELECT
  'msg_' || substr(md5(m.protocol_number || ':' || m.k::text), 1, 20),
  m.protocol_number,
  CASE WHEN m.k % 2 = 1 THEN NULL
       WHEN m.is_backlog THEN 'ai_01'
       WHEN m.conv_type = 'mixed' AND m.k = 2 THEN 'ai_01'
       ELSE m.agent_id END,
  CASE WHEN m.k % 2 = 1 THEN 'customer'
       WHEN m.is_backlog THEN 'ai'
       WHEN m.conv_type = 'ai' THEN 'ai'
       WHEN m.conv_type = 'human' THEN 'human'
       WHEN m.k = 2 THEN 'ai'
       ELSE 'human' END,
  m.opened_at + make_interval(secs => m.offset_secs),
  m.opened_at + make_interval(secs => m.offset_secs) + interval '2 seconds',
  m.sleekflow_conversation_id
FROM (
  SELECT c.*, k.k,
         CASE WHEN c.is_backlog THEN (k.k - 1) * 120.0
              WHEN k.k = 1 THEN 0.0
              ELSE c.frt + (c.aht - c.frt) * (k.k - 2)::double precision / (c.n_msgs - 2)
         END AS offset_secs
  FROM (
    SELECT d.*,
      CASE WHEN d.is_backlog
           THEN 1 + floor(pg_temp.demo_rand(d.i::text || ':nb') * 3)::int
           ELSE 2 * CASE d.conv_type
                      WHEN 'ai'    THEN 2 + floor(pg_temp.demo_rand(d.i::text || ':nm') * 4)::int
                      WHEN 'human' THEN 3 + floor(pg_temp.demo_rand(d.i::text || ':nm') * 4)::int
                      ELSE              3 + floor(pg_temp.demo_rand(d.i::text || ':nm') * 5)::int
                    END
      END AS n_msgs
    FROM demo_conv AS d
  ) AS c
  CROSS JOIN LATERAL generate_series(1, c.n_msgs) AS k(k)
) AS m
ORDER BY m.i, m.k;

-- 6.7 CSAT responses (about 27% of closed conversations)
INSERT INTO public.fact_csat_responses
  (conversation_id, csat_value, responded_at, created_at, detractor_reason_id, detractor_summary)
SELECT
  x.protocol_number,
  x.csat_value,
  x.responded_at,
  x.responded_at + interval '5 seconds',
  dr.detractor_reason_id,
  CASE x.reason_name
    WHEN 'Response Time / Delay'             THEN 'Customer complained about the wait for a reply.'
    WHEN 'Issue Not Resolved'                THEN 'Customer said the issue was not actually solved.'
    WHEN 'Agent Tone / Empathy'              THEN 'Customer felt the support tone was not empathetic.'
    WHEN 'Product Limitation'                THEN 'Customer was unhappy with a product limitation.'
    WHEN 'Repetitive / Had to Explain Again' THEN 'Customer had to repeat the same information.'
    WHEN 'Other'                             THEN 'Customer gave a reason outside the listed categories.'
  END
FROM (
  SELECT
    v.*,
    CASE WHEN v.csat_value <> 'unsatisfied' THEN NULL
         WHEN NOT v.sla_met AND v.r_reason1 < 0.5 THEN 'Response Time / Delay'
         ELSE (ARRAY['Issue Not Resolved', 'Agent Tone / Empathy', 'Product Limitation',
                     'Repetitive / Had to Explain Again', 'Other'])[1 + floor(v.r_reason2 * 5)::int]
    END AS reason_name
  FROM (
    SELECT
      c.i, c.protocol_number, c.sla_met,
      c.closed_at + make_interval(secs => 60 + floor(pg_temp.demo_rand(c.i::text || ':rt') * 21540)::int) AS responded_at,
      pg_temp.demo_rand(c.i::text || ':rs1') AS r_reason1,
      pg_temp.demo_rand(c.i::text || ':rs2') AS r_reason2,
      CASE WHEN c.sla_met
           THEN CASE WHEN pg_temp.demo_rand(c.i::text || ':cv') < 0.80 THEN 'satisfied'
                     WHEN pg_temp.demo_rand(c.i::text || ':cv') < 0.94 THEN 'neutral'
                     ELSE 'unsatisfied' END
           ELSE CASE WHEN pg_temp.demo_rand(c.i::text || ':cv') < 0.50 THEN 'satisfied'
                     WHEN pg_temp.demo_rand(c.i::text || ':cv') < 0.74 THEN 'neutral'
                     ELSE 'unsatisfied' END
      END AS csat_value
    FROM demo_conv AS c
    WHERE NOT c.is_backlog
      AND pg_temp.demo_rand(c.i::text || ':csat') < 0.27
  ) AS v
) AS x
LEFT JOIN public.dim_detractor_reasons AS dr ON dr.reason_name = x.reason_name
ORDER BY x.i;

COMMIT;

-- Quick check for section 6 (integrity checks must be 0)
SELECT check_name, found
FROM (
  SELECT 1 AS ord, 'sessions' AS check_name, (SELECT COUNT(*) FROM public.dim_conversation_sessions) AS found
  UNION ALL SELECT 2, 'sessions closed',  (SELECT COUNT(*) FROM public.dim_conversation_sessions WHERE status = 'closed')
  UNION ALL SELECT 3, 'sessions open (backlog)', (SELECT COUNT(*) FROM public.dim_conversation_sessions WHERE status = 'open')
  UNION ALL SELECT 4, 'fact_conversations', (SELECT COUNT(*) FROM public.fact_conversations)
  UNION ALL SELECT 5, 'fact_messages',      (SELECT COUNT(*) FROM public.fact_messages)
  UNION ALL SELECT 6, 'fact_csat_responses', (SELECT COUNT(*) FROM public.fact_csat_responses)
  UNION ALL SELECT 7, 'view rows (expect 636)', (SELECT COUNT(*) FROM public.vw_support_dashboard)
  UNION ALL SELECT 8, 'INTEGRITY: facts without session',
         (SELECT COUNT(*) FROM public.fact_conversations f
           WHERE NOT EXISTS (SELECT 1 FROM public.dim_conversation_sessions s WHERE s.protocol_number = f.protocol_number))
  UNION ALL SELECT 9, 'INTEGRITY: messages without session',
         (SELECT COUNT(*) FROM public.fact_messages m
           WHERE NOT EXISTS (SELECT 1 FROM public.dim_conversation_sessions s WHERE s.protocol_number = m.protocol_number))
  UNION ALL SELECT 10, 'INTEGRITY: closed sessions without fact',
         (SELECT COUNT(*) FROM public.dim_conversation_sessions s
           WHERE s.status = 'closed'
             AND NOT EXISTS (SELECT 1 FROM public.fact_conversations f WHERE f.protocol_number = s.protocol_number))
) AS c
ORDER BY ord;
