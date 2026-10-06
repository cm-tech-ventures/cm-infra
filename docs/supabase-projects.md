# Projetos Supabase da CM Ventures

Registro de posse dos bancos Postgres/Supabase usados pelos sistemas da empresa.
Fonte de verdade para saber, a qualquer momento, em qual conta cada projeto vive
e quem é responsável por manter o keep-alive (CMV-53) cobrindo-o.

## Convenção

- **Ativos de core** (CM Ventures) ficam na conta corporativa
  `cm.tech.ventures@gmail.com` (mesmo e-mail dono do GCP `cm-ventures-core` —
  ver PLANEJAMENTO.md §2.4).
- **Ativos de vertical** ficam na conta de TI da própria vertical — mesma lógica
  da separação de projetos GCP (`cm-ventures-core` vs `md-hom`/`md-prd`). Para o
  MD (Meus Dredinhos), a conta de TI é `ti.meusdredinhos@gmail.com`.
  Correção do board em [CMV-54](/CMV/issues/CMV-54): o destino **não** é a conta
  corporativa da CM Ventures.
- Nenhum projeto de produção deve ficar em conta pessoal de qualquer membro do board.
- Toda mudança de posse (transferência de organização Supabase) deve ser registrada
  nesta tabela com data e issue de referência.

## Projetos

| Sistema        | Project ref            | Organização Supabase (dona)         | Status                | Issue |
|----------------|-------------------------|--------------------------------------|------------------------|-------|
| cores (CM Ventures) | (ver `cm-ventures-core` / Secret Manager) | `cm.tech.ventures@gmail.com`         | OK — nasceu corporativo | — |
| `md-backend`: MD produção (GCP `md-hom`) | `jwyjqiezwjccnxrbmlai` | `ti.meusdredinhos` | OK, já na org da vertical; DSN no keep-alive desde 2026-10-06 | [CMV-54](/CMV/issues/CMV-54), [cm-infra#59](https://github.com/cm-tech-ventures/cm-infra/issues/59) |
| `md-backend-prod`: MD homologação (GCP `md-hlg`) | `ajjlyugjutltxyepzbhk` | `ti.meusdredinhos` | OK; DSN no keep-alive desde 2026-10-06 | [cm-infra#59](https://github.com/cm-tech-ventures/cm-infra/issues/59) |
| `sys-bjj-backend` (bjj-system) | `aoriyfujsilisrrvadxy` | conta da vertical BJJ | OK — DSN incluído no keep-alive em 2026-07-29 | [CMV-297](/CMV/issues/CMV-297) |

> Os nomes do MD enganam. O projeto Supabase `md-backend` é a **produção**: é o
> banco real do salão, servido hoje pelo GCP `md-hom`. O `md-backend-prod` é a
> **homologação** nova, ligada ao GCP `md-hlg`. Ver a virada de ambientes em
> [md-backend#308](https://github.com/cadusds2/md-backend/issues/308).
>
> A transferência do `md-backend` para a org `ti.meusdredinhos` (CMV-54) já foi
> feita: em 06/10/2026 o projeto aparece nessa org. A data exata da
> transferência não ficou registrada. O runbook abaixo fica como referência
> para próximas transferências.

## Runbook — transferência de organização (sem downtime)

Executado pelo **board** (exige login nas contas Supabase envolvidas; o agente
Platform Engineer não tem credenciais de dashboard SaaS).

1. Na conta `ti.meusdredinhos@gmail.com`, criar (ou reaproveitar) uma
   organização Supabase da vertical MD, caso ainda não exista.
2. Na conta pessoal do Carlos, abrir o projeto `jwyjqiezwjccnxrbmlai`
   (`backend-md` / md-hom) → **Project Settings → General → Transfer project**.
   - Alternativa se o botão não aparecer no free-tier: convidar a conta
     `ti.meusdredinhos@gmail.com` como membro/owner temporário do projeto
     primeiro, depois repetir o transfer a partir dela.
3. Selecionar a organização de `ti.meusdredinhos@gmail.com` como destino e confirmar.
4. **Não** alterar nada em `DATABASE_URL` / connection string a menos que o
   Supabase avise explicitamente que ela mudou — transferência de organização
   preserva o project ref e as credenciais existentes.
5. Confirmar no dashboard que o projeto aparece sob a organização de
   `ti.meusdredinhos@gmail.com` e que a conta pessoal do Carlos não é mais
   "Owner" (pode continuar como membro convidado, se desejado, mas não deve
   ser a dona).

### Plano B — se a transferência não estiver disponível

Só usar se o passo 2 acima não for oferecido pelo Supabase no tier atual do projeto:

1. Criar projeto novo na conta `ti.meusdredinhos@gmail.com`.
2. `pg_dump` do projeto atual (`jwyjqiezwjccnxrbmlai`) e `pg_restore` no projeto novo.
3. Atualizar `DATABASE_URL` no Cloud Run `backend-md` (md-hom) e no job de
   migração/keep-alive apontando para o novo host.
4. Exige janela de manutenção curta — combinar horário com o board antes de
   executar (usuários do MD ficam sem login durante o dump/restore).

## Verificação pós-migração (papel do agente)

Depois que o board confirmar a transferência (Plano A) ou o cutover (Plano B):

1. Testar login no frontend do MD (md-hom) — sessão autenticando normalmente.
2. Conferir execução verde do(s) job(s) do `backend-md` que dependem do banco
   (ex.: jobs agendados / Cloud Run Jobs).
3. Garantir que `KEEPALIVE_DB_DSNS` (Secret Manager, job `jobs/keepalive` neste
   repo) inclui o DSN deste banco — ver [CMV-53](/CMV/issues/CMV-53).
4. Atualizar a tabela acima para "OK — migrado em `<data>`".
5. Conferir que nenhuma env var / secret em `backend-md` (md-hom) ainda referencia
   a conta pessoal (ex.: comentários, README, `.env.example`).
