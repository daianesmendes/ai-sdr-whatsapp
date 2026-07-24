# Agente de IA SDR — Acompanhamento Comercial Pós-Reunião (n8n)

Automação de acompanhamento de leads no pós-reunião comercial, construída em **n8n**.
Cobre desde o disparo automático de mensagens até um **agente de IA (SDR)** que
conversa com o lead pelo WhatsApp, com **revisão humana antes do envio**,
notificações para vendedor/gestor e memória de conversa.

> ⚠️ **Fluxos sanitizados para portfólio.** Todas as credenciais, chaves de API,
> URLs internas, telefones, IDs de usuário e nomes de pessoas/empresa foram
> substituídos por placeholders. Nenhum segredo real está presente neste repositório.

## Arquitetura

São 4 workflows que se chamam entre si:

| # | Workflow | Papel |
|---|----------|-------|
| 01 | `comercial-01-envio-mensagens-automaticas` | 3 réguas agendadas (pós-apresentação, reaquecer, reaquecer_paçoca) que enfileiram mensagens/áudios de acompanhamento, com marcador anti-duplicidade. |
| 02 | `comercial-02-atendimento-ia-leads` | Núcleo. Recebe a resposta do lead (texto/áudio/imagem), faz *buffer* de mensagens no Redis, monta contexto, chama o agente SDR (OpenAI com JSON Schema) e orquestra o envio. |
| 03 | `comercial-03-aprovacao-handoff` | Revisão humana: aprovar / reprovar (reescrever) / parar (handoff para humano), operada por um grupo de WhatsApp. |
| 04 | `comercial-04-notificacoes-vendedor-gestor` | Notifica o vendedor responsável (resumo do lead) e o gestor (somente em reclamação). |

## Destaques técnicos

- **Buffer de mensagens no Redis** com janela de tempo + verificação de "última mensagem"
  (evita responder a cada mensagem picada; consolida antes de acionar a IA).
- **Agente com saída estruturada** (`json_schema` / `strict`): a IA devolve um objeto
  tipado (`responder`, `mensagem`, `encerrar`, `classificacao`, `notificar_vendedor`,
  `notificar_gestor`, ...) em vez de texto livre — reduz parsing frágil e custo de tokens.
- **Human-in-the-loop**: nenhuma resposta vai ao lead sem aprovação, via comandos
  simples (*aprovar / reprovar / parar*) num grupo de WhatsApp.
- **Multimodal**: transcrição de áudio (Whisper) e descrição/OCR de imagens antes de
  entrar no contexto do agente.
- **Memória de conversa** em Postgres + **máquina de estados** da conversa
  (`ativa` / `aguardando_aprovacao` / `handoff`).
- Prompt com **guardrails**: o agente não passa preço/condições, não inventa dados e
  respeita pedidos de não-contato.

## Como usar

1. Importe os `.json` de `workflows/` no seu n8n.
2. Recrie as credenciais (SQL Server, Postgres, Redis, OpenAI) — os nós referenciam
   placeholders (`CRED_*`) e pedirão reconexão.
3. Substitua os placeholders de infraestrutura:
   - `YOUR_WAHA_API_KEY`, `http://waha.internal.local`, `waha-session-001`
   - IDs de telefone/grupo (`120363000000000000@g.us`, `55000000000x`)
   - `user_id = '000000'`
4. Ajuste os nomes de tabelas do banco conforme seu schema.

## Stack

n8n · OpenAI (GPT + Whisper) · WhatsApp (WAHA) · Redis · PostgreSQL · SQL Server
