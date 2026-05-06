# Contrato de Ambiente

Padrão de conexão para desenvolvimento local, Docker Compose e banco compartilhado.

## Modos Oficiais

| Modo | Uso | Host | Porta | Arquivo |
| --- | --- | --- | --- | --- |
| Local | Scripts, DBeaver, pgAdmin local | `localhost` | `5432` | `.env.example` |
| Docker | Backend, API e simulador no mesmo Compose | `postgres` | `5432` | `.env.docker.example` |
| Compartilhado | Time usando um PostgreSQL remoto | valor do provedor | `5432` | `.env.shared.example` |
| Supabase | Time usando Supabase Postgres | pooler ou host direto | `5432` ou `6543` | `.env.supabase.example` |

## Local

Credenciais padrão:

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

Serviços dentro do mesmo Compose devem usar o host `postgres`, que é o nome do serviço no `docker-compose.yml`.

```txt
postgresql://parking:parking123@postgres:5432/monolith_parking
```

## Banco Compartilhado

O repositório não contém host remoto real. O grupo deve provisionar um PostgreSQL e preencher:

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

`DATABASE_ADMIN_URL` deve ter permissão para criar roles e conceder privilégios. Em provedores que não permitem `CREATE ROLE`, os usuários devem ser criados no painel do provedor e o script de grants pode falhar por limitação da plataforma.

## Supabase

No Supabase, o database padrão normalmente é `postgres`. Copie `.env.supabase.example` para `.env` e use a string do painel `Connect`.

Recomendação para o grupo:

- usar a connection string do `Session pooler` para acesso compartilhado e ferramentas locais;
- no pooler, usar usuário no formato `<role>.<project-ref>`;
- usar `PGSSLMODE=require`;
- manter a senha real fora do Git;
- codificar caracteres especiais da senha na URL, se houver.

## Regras

- `.env` real não deve ser commitado.
- Senhas reais não devem aparecer em Markdown.
- Serviços devem ler `DATABASE_URL`.
- Scripts deste módulo procuram `.env` em `backend/database`.
- Após mudanças no schema, rode `npm run bootstrap:shared` para alinhar o banco remoto.
