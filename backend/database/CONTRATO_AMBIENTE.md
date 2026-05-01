# Contrato de ambiente

Padrao de conexao para desenvolvimento local, Docker Compose e banco compartilhado.

## Modos oficiais

| Modo | Uso | Host | Porta | Arquivo |
| --- | --- | --- | --- | --- |
| Local | Scripts, DBeaver, pgAdmin local | `localhost` | `5432` | `.env.example` |
| Docker | Backend/API/simulador no mesmo Compose | `postgres` | `5432` | `.env.docker.example` |
| Compartilhado | Time usando um Postgres remoto | valor do provedor | `5432` | `.env.shared.example` |
| Supabase | Time usando Supabase Postgres | pooler ou direct host | `5432` ou `6543` | `.env.supabase.example` |

## Local

Credenciais padrao:

```txt
database: monolith_parking
user: parking
password: parking123
```

`DATABASE_URL`:

```txt
postgresql://parking:parking123@localhost:5432/monolith_parking
```

## Docker Compose

Servicos dentro do mesmo Compose devem usar o host `postgres`, que e o nome do servico no `docker-compose.yml`.

```txt
postgresql://parking:parking123@postgres:5432/monolith_parking
```

## Banco compartilhado

O repositorio nao contem host remoto real. O grupo deve provisionar um PostgreSQL e preencher:

```txt
DATABASE_ADMIN_URL=postgresql://admin_user:<senha>@<host>:5432/monolith_parking
DATABASE_WRITER_USER=parking_writer
DATABASE_WRITER_PASSWORD=<senha_writer>
DATABASE_READER_USER=parking_reader
DATABASE_READER_PASSWORD=<senha_reader>
DATABASE_URL=postgresql://parking_writer:<senha>@<host>:5432/monolith_parking
TEAM_READER_DATABASE_URL=postgresql://parking_reader:<senha>@<host>:5432/monolith_parking
PGSSLMODE=require
```

Depois:

```powershell
npm run bootstrap:shared
npm run setup:shared-access
npm run check:requirements
npm run check:db
npm run check:shared-access
```

`DATABASE_ADMIN_URL` deve ter permissao para criar roles e conceder privilegios. Em provedores que nao permitem `CREATE ROLE`, os usuarios devem ser criados no painel do provedor e o script de grants pode falhar por limitacao da plataforma.

## Supabase

No Supabase, o database padrao normalmente e `postgres`. Copie `.env.supabase.example` para `.env` e use a string do painel `Connect`.

Recomendacao para o grupo:

- usar a connection string do `Session pooler` para acesso compartilhado e ferramentas locais;
- no pooler, usar usuario no formato `<role>.<project-ref>`;
- usar `PGSSLMODE=require`;
- manter a senha real fora do Git;
- codificar caracteres especiais da senha na URL, se houver.

## Regras

- `.env` real nao deve ser commitado.
- Senhas reais nao devem aparecer em Markdown.
- Servicos devem ler `DATABASE_URL`.
- Scripts deste modulo procuram `.env` em `backend/database`.
