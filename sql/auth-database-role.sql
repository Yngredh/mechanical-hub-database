-- ============================================================================
-- Usuario de banco dedicado a autenticacao.
--
-- Pertence a este repositorio por decisao da ADR-0002: a "definicao do
-- usuario/role de banco com privilegio minimo utilizado pela autenticacao" e
-- responsabilidade do mechanical-hub-database. O script vivia no
-- mechanical-hub-auth ate a reorganizacao dos repositorios.
--
-- Principio: a funcao de autenticacao le duas tabelas e nada mais. Se um dia
-- ela for comprometida, o alcance do estrago para em SELECT.
--
-- Fase 4: a role vive na instancia do `orders` (output auth_database), dona
-- de `users` e `profiles`. Este script cria apenas a role com LOGIN e CONNECT;
-- o GRANT SELECT nas tabelas fica na migration Flyway do
-- `mechanical-hub-orders`, que cria essas tabelas.
--
-- ---------------------------------------------------------------------------
-- QUANDO EXECUTAR
-- ---------------------------------------------------------------------------
-- Depois de:
--   1. `terraform apply` deste repositorio ter criado a instancia do orders;
--   2. sql/service-user.sql ter rodado nessa instancia (o REVOKE de CONNECT
--      para PUBLIC feito la e o motivo do GRANT CONNECT explicito abaixo).
--
-- Antes de:
--   3. o primeiro deploy do `mechanical-hub-orders` — suas migrations
--      concedem o SELECT a esta role e falham se ela nao existir;
--   4. o deploy do `mechanical-hub-auth`, que conecta com esta role.
--
-- ---------------------------------------------------------------------------
-- COMO EXECUTAR
-- ---------------------------------------------------------------------------
-- Pela pipeline (recomendado): Actions -> Deploy -> Run workflow. A senha vem
-- do secret AUTH_DB_PASSWORD.
--
-- Manualmente, com o usuario master, conectado ao banco do orders:
--
--   psql "host=<auth_database.endpoint> port=5432 dbname=mechanical_hub_orders \
--         user=mechanical_hub_admin sslmode=require" \
--        -v ON_ERROR_STOP=1 \
--        -v auth_password="minha-senha-forte" \
--        -f sql/auth-database-role.sql
--
-- A senha e passada sem aspas: o `:'auth_password'` abaixo pede ao psql para
-- transforma-la em literal SQL com o escape correto.
--
-- O script e idempotente — pode rodar a cada reset do ambiente sem erro, e
-- tambem depois das migrations do orders (nao mexe nos SELECT concedidos).
-- ============================================================================

\set ON_ERROR_STOP on

-- A senha entra numa configuracao de sessao porque o psql NAO interpola
-- variaveis dentro de strings dollar-quoted ($$...$$) — dentro do bloco DO
-- abaixo, `:auth_password` chegaria literal e quebraria. `current_setting`
-- resolve isso sem expor a senha em nenhum objeto persistente.
SELECT set_config('mechanical_hub.auth_password', :'auth_password', false);

-- ---------------------------------------------------------------------------
-- Role
-- ---------------------------------------------------------------------------
-- CREATE ROLE falha se a role ja existe, e o ambiente do laboratorio e
-- recriado do zero com frequencia. O bloco cria na primeira execucao e apenas
-- atualiza a senha nas seguintes.
DO $$
DECLARE
    senha text := current_setting('mechanical_hub.auth_password');
BEGIN
    IF senha IS NULL OR length(senha) = 0 THEN
        RAISE EXCEPTION 'Senha vazia. Informe -v auth_password=<senha> ao psql.';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mechanical_hub_auth') THEN
        EXECUTE format('ALTER ROLE mechanical_hub_auth WITH LOGIN PASSWORD %L', senha);
        RAISE NOTICE 'Role mechanical_hub_auth ja existia — senha atualizada.';
    ELSE
        EXECUTE format('CREATE ROLE mechanical_hub_auth WITH LOGIN PASSWORD %L', senha);
        RAISE NOTICE 'Role mechanical_hub_auth criada.';
    END IF;
END
$$;

-- A senha ja cumpriu seu papel; nao precisa continuar legivel na sessao.
SELECT set_config('mechanical_hub.auth_password', '', false);

-- ---------------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------------
-- GRANT e idempotente por natureza: reconceder o mesmo privilegio nao e erro.
-- O nome do banco vem de current_database() para nao fixar o nome aqui.
--
-- Sem GRANT SELECT: users e profiles ainda nao existem quando este script
-- roda. A migration do orders concede o SELECT nas colunas usadas pelo login.

SELECT format('GRANT CONNECT ON DATABASE %I TO mechanical_hub_auth', current_database()) \gexec

-- ---------------------------------------------------------------------------
-- Verificacao
-- ---------------------------------------------------------------------------
-- Falha explicita se a role nao conecta ou acabou com qualquer privilegio de
-- escrita (vale tambem quando o script roda de novo depois das migrations).
DO $$
DECLARE
    escritas integer;
BEGIN
    IF NOT has_database_privilege('mechanical_hub_auth', current_database(), 'CONNECT') THEN
        RAISE EXCEPTION 'mechanical_hub_auth ficou sem CONNECT em %.', current_database();
    END IF;

    SELECT count(*) INTO escritas
      FROM (
          SELECT privilege_type
            FROM information_schema.role_table_grants
           WHERE grantee = 'mechanical_hub_auth'
          UNION ALL
          SELECT privilege_type
            FROM information_schema.role_column_grants
           WHERE grantee = 'mechanical_hub_auth'
      ) g
     WHERE g.privilege_type <> 'SELECT';

    IF escritas > 0 THEN
        RAISE EXCEPTION
            'mechanical_hub_auth tem % privilegio(s) alem de SELECT.', escritas;
    END IF;

    RAISE NOTICE 'Verificacao OK: mechanical_hub_auth conecta em % e nao tem privilegio de escrita.', current_database();
END
$$;
