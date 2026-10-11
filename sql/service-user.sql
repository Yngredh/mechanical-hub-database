-- ============================================================================
-- Usuario de banco de um servico (orders, stock ou billing).
--
-- ADR-0004: cada servico tem sua propria instancia RDS e seu proprio usuario.
-- O usuario master da instancia fica restrito a administracao; a aplicacao
-- conecta com o usuario criado aqui, que e dono do schema `public` e, por
-- consequencia, das tabelas criadas pelas migrations Flyway do servico.
--
-- ---------------------------------------------------------------------------
-- QUANDO EXECUTAR
-- ---------------------------------------------------------------------------
-- Uma vez por instancia, depois do `terraform apply` deste repositorio e antes
-- do primeiro deploy do servico (as migrations rodam com este usuario). Na
-- instancia do `orders`, antes de sql/auth-database-role.sql.
--
-- ---------------------------------------------------------------------------
-- COMO EXECUTAR
-- ---------------------------------------------------------------------------
-- Pela pipeline (recomendado): Actions -> Deploy -> Run workflow. A senha vem
-- do secret <SERVICO>_DB_APP_PASSWORD (ORDERS, STOCK, BILLING).
--
-- Manualmente, com o usuario master, conectado ao banco do servico:
--
--   psql "host=<endpoint> port=5432 dbname=mechanical_hub_orders \
--         user=mechanical_hub_admin sslmode=require" \
--        -v ON_ERROR_STOP=1 \
--        -v service_user=orders_app \
--        -v service_password="minha-senha-forte" \
--        -f sql/service-user.sql
--
-- Os valores sao passados sem aspas: `:'service_user'` e `:'service_password'`
-- pedem ao psql para transforma-los em literais SQL com o escape correto.
--
-- O script e idempotente — pode rodar a cada reset do ambiente sem erro; nas
-- execucoes seguintes apenas atualiza a senha.
-- ============================================================================

\set ON_ERROR_STOP on

-- Os valores entram em configuracoes de sessao porque o psql NAO interpola
-- variaveis dentro de strings dollar-quoted ($$...$$).
SELECT set_config('mechanical_hub.service_user', :'service_user', false);
SELECT set_config('mechanical_hub.service_password', :'service_password', false);

-- ---------------------------------------------------------------------------
-- Usuario
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    usuario text := current_setting('mechanical_hub.service_user');
    senha   text := current_setting('mechanical_hub.service_password');
BEGIN
    IF usuario IS NULL OR usuario !~ '^[a-z_][a-z0-9_]*$' THEN
        RAISE EXCEPTION 'service_user invalido: "%". Use letras minusculas, digitos e _.', usuario;
    END IF;

    IF senha IS NULL OR length(senha) = 0 THEN
        RAISE EXCEPTION 'Senha vazia. Informe -v service_password=<senha> ao psql.';
    END IF;

    IF usuario = current_user THEN
        RAISE EXCEPTION 'service_user nao pode ser o usuario master (%).', current_user;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = usuario) THEN
        EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', usuario, senha);
        RAISE NOTICE 'Usuario % ja existia — senha atualizada.', usuario;
    ELSE
        EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', usuario, senha);
        RAISE NOTICE 'Usuario % criado.', usuario;
    END IF;
END
$$;

-- A senha ja cumpriu seu papel; nao precisa continuar legivel na sessao.
SELECT set_config('mechanical_hub.service_password', '', false);

-- ---------------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------------
-- Nomes de banco e usuario variam por instancia, entao os comandos sao
-- montados com format(%I) e executados pelo \gexec do psql.

-- Ninguem conecta por padrao: cada role recebe CONNECT explicitamente (este
-- usuario aqui; mechanical_hub_auth em sql/auth-database-role.sql).
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I',
              current_database(), :'service_user') \gexec

-- No PostgreSQL 16 quem cria a role nao herda o direito de agir como ela; o
-- master precisa ser membro para transferir a propriedade do schema.
SELECT format('GRANT %I TO %I', :'service_user', current_user) \gexec

-- Dono do schema: as migrations criam as tabelas e concedem privilegios sobre
-- elas (ex.: o GRANT SELECT do orders para mechanical_hub_auth).
SELECT format('ALTER SCHEMA public OWNER TO %I', :'service_user') \gexec
SELECT format('GRANT USAGE, CREATE ON SCHEMA public TO %I', :'service_user') \gexec

-- ---------------------------------------------------------------------------
-- Verificacao
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    usuario text := current_setting('mechanical_hub.service_user');
BEGIN
    IF NOT has_database_privilege(usuario, current_database(), 'CONNECT') THEN
        RAISE EXCEPTION '% ficou sem CONNECT em %.', usuario, current_database();
    END IF;

    IF (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname = 'public') <> quote_ident(usuario) THEN
        RAISE EXCEPTION 'O schema public nao ficou com % como dono.', usuario;
    END IF;

    RAISE NOTICE 'Verificacao OK: % conecta em % e e dono do schema public.', usuario, current_database();
END
$$;
