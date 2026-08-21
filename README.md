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
| 02 | `comercial-02-atendimento-ia-leads` | Núcleo. Recebe a resposta do lead (texto/áudio/imagem), faz *buffer* de mensagens no Redis, **consulta a base de conhecimento (pgvector)**, monta contexto, chama o agente SDR (OpenAI com JSON Schema) e orquestra o envio. |
| 03 | `comercial-03-aprovacao-handoff` | Revisão humana: aprovar / reprovar (reescrever) / parar (handoff), operada por um grupo de WhatsApp — **por texto ou por áudio**. A correção humana também vira **conhecimento** na base vetorial. |
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
- **Base de conhecimento que aprende com a revisão humana** (RAG em pgvector): quando
  a resposta da IA é reprovada e um humano escreve a correta, um LLM transforma o par
  (mensagem do lead + correção) em um **trecho de conhecimento declarativo** — não um
  par pergunta/resposta e não a mensagem pronta — que é embeddado e gravado em `kb_faq`.
  O agente consulta essa base em toda mensagem seguinte. Cada correção melhora o agente.
- **Aprovação por áudio**: quem revisa costuma estar no celular, sem tempo de digitar.
  Os comandos aceitam voz ("sim", "não", "pausa") e a própria mensagem correta pode ser
  ditada. O parser separa comando de conteúdo e trata o caso ambíguo — uma correção que
  começa com "Não temos isso hoje..." não é confundida com o comando *reprovar*.
- Prompt com **guardrails**: o agente não passa preço/condições, não inventa dados e
  respeita pedidos de não-contato.

## Decisões de engenharia (o que não é óbvio no JSON)

- **RAG por injeção, não por *tool*.** O requisito é buscar a cada mensagem; *tool* é
  opcional por natureza (o modelo decide se chama, e com `reasoning: low` costuma não
  chamar). Injetar o resultado no prompt torna a consulta determinística. Bônus: o nó
  *Message a Model* do n8n não serializa bem a entrada de tools estruturadas — a tool do
  vector store falha com `Received tool input did not match expected schema`.
- **Conhecimento declarativo em vez de par P/R.** Guardar `"P: ... R: ..."` faz o agente
  repetir resposta pronta. Guardar *"Negociação e condições: quando o lead quer negociar,
  o assunto é encaminhado ao vendedor responsável"* faz o agente **escrever** a mensagem
  dele com a informação certa.
- **Limiar de similaridade medido, não chutado.** Com `text-embedding-3-small`, uma
  paráfrase quase idêntica pontuou **0.661** — ou seja, o teto prático é ~0.7 e um corte
  em 0.70 descartava conhecimento relevante em silêncio. O limiar em uso é **0.50**.
  Antes de escolher o número, rode a busca sem filtro e olhe o `score` real.
- **Citação só quando é ambíguo.** A revisão acontece num grupo, e exigir que a SDR
  sempre responda *citando* a card é atrito desnecessário quando há uma única pendência.
  O fluxo conta as pendências abertas: com uma, aceita a resposta solta; com mais de uma,
  avisa no grupo e pede a citação em vez de adivinhar e mandar a resposta ao lead errado.
- **Falha da base não derruba a conversa.** Os nós de embedding e busca usam
  `onError: continue` + `alwaysOutputData`: se a OpenAI ou o Postgres caírem, o agente
  responde sem conhecimento em vez de deixar o lead sem resposta.

## Como usar

1. Importe os `.json` de `workflows/` no seu n8n.
2. Recrie as credenciais (SQL Server, Postgres, Redis, OpenAI) — os nós referenciam
   placeholders (`CRED_*`) e pedirão reconexão.
3. Substitua os placeholders de infraestrutura:
   - `YOUR_WAHA_API_KEY`, `http://waha.internal.local`, `waha-session-001`
   - IDs de telefone/grupo (`120363000000000000@g.us`, `55000000000x`)
   - `user_id = '000000'`
4. Ajuste os nomes de tabelas do banco conforme seu schema.
5. Rode `sql/kb_faq.sql` no Postgres (cria a extensão `vector`, a tabela `kb_faq` e o
   índice HNSW). No nó *PGVector Store* do fluxo 03, confira as **Column Names**
   (`id` / `embedding` / `text` / `metadata`) — o default do nó para o vetor é `vector`,
   e aqui a coluna se chama `embedding`.

## Stack

n8n · OpenAI (GPT + Whisper + Embeddings) · WhatsApp (WAHA) · Redis · PostgreSQL + pgvector · SQL Server
