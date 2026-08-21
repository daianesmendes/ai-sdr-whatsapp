-- =============================================================
-- Base de conhecimento do agente SDR (pgvector)
-- Alimentada pelo fluxo 03 (correções humanas) e consultada pelo fluxo 02.
-- Rodar uma vez no Postgres do agente.
-- =============================================================

CREATE EXTENSION IF NOT EXISTS vector;
-- Postgres < 13: descomente para ter gen_random_uuid()
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Colunas no formato esperado pelo nó "Postgres PGVector Store" do n8n.
-- A coluna do vetor se chama 'embedding' (o default do nó é 'vector'), então
-- nas Options do nó preencha Column Names: id / embedding / text / metadata.
CREATE TABLE IF NOT EXISTS kb_faq (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  text       text,          -- o trecho de conhecimento (é o que foi embeddado)
  metadata   jsonb,         -- deal_id, telefone, origem, por_audio, mensagem_lead
  embedding  vector(1536),  -- text-embedding-3-small
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS kb_faq_embedding_idx
  ON kb_faq USING hnsw (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS kb_faq_created_at_idx
  ON kb_faq (created_at DESC);

-- =============================================================
-- Consultas úteis
-- =============================================================

-- O que o agente já aprendeu (vale revisar nas primeiras semanas: o risco não é
-- a mecânica, é o LLM generalizar demais ou de menos).
-- SELECT id, created_at, left(text, 120) AS conhecimento,
--        metadata->>'deal_id' AS deal_id, metadata->>'por_audio' AS por_audio
--   FROM kb_faq ORDER BY created_at DESC LIMIT 20;

-- Calibrar o limiar: rode SEM o filtro para ver os scores reais antes de
-- escolher um número. Trocar o vetor pelo embedding de uma pergunta de teste.
-- SELECT text, ROUND((1 - (embedding <=> '[...]'::vector))::numeric, 3) AS score
--   FROM kb_faq ORDER BY embedding <=> '[...]'::vector LIMIT 5;
