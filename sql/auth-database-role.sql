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
-- ---------------------------------------------------------------------------
-- QUANDO EXECUTAR
-- ---------------------------------------------------------------------------
-- Depois de:
--   1. `terraform apply` deste repositorio ter criado a instancia RDS;
--   2. as migrations Flyway V18, V19 e V20 do `mechanical-hub` terem sido
--      aplicadas — sao elas que criam e populam `users.document_number`, a
--      coluna usada pelo login. Sem elas o GRANT abaixo falha com
--      "column document_number does not exist".
--
-- Antes de:
--   3. o primeiro deploy do `mechanical-hub-auth`, que ja sobe configurado
--      para conectar com esta role.
--
-- ---------------------------------------------------------------------------
-- COMO EXECUTAR
-- ---------------------------------------------------------------------------
-- Pela pipeline (recomendado): Actions -> Deploy -> Run workflow, marcando
-- "criar_role_de_autenticacao". A senha vem do secret AUTH_DB_PASSWORD.
--
-- Manualmente, com o usuario master:
--
--   psql "host=<rds_endpoint> port=5432 dbname=mechanical_hub \
--         user=mechanical_hub sslmode=require" \
--        -v ON_ERROR_STOP=1 \
--        -v auth_password="minha-senha-forte" \
--        -f sql/auth-database-role.sql
--
-- A senha e passada sem aspas: o `:'auth_password'` abaixo pede ao psql para
-- transforma-la em literal SQL com o escape correto.
--
-- O script e idempotente — pode rodar a cada reset do ambiente sem erro.
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

-- ---------------------------------------------------------------------------
-- Privilegios
-- ---------------------------------------------------------------------------
-- GRANT e idempotente por natureza: reconceder o mesmo privilegio nao e erro.

GRANT CONNECT ON DATABASE mechanical_hub TO mechanical_hub_auth;
GRANT USAGE ON SCHEMA public TO mechanical_hub_auth;

-- Apenas as colunas que a consulta de login usa. password_hash entra porque a
-- verificacao de senha acontece na funcao; nenhuma outra coluna e exposta.
GRANT SELECT (id, name, document_number, password_hash, deleted_at, profile_id)
    ON users TO mechanical_hub_auth;

GRANT SELECT ON profiles TO mechanical_hub_auth;

-- Garantia explicita: sem escrita, sem acesso as demais tabelas de dominio.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public FROM mechanical_hub_auth;

-- Tabelas criadas no futuro nao devem ficar visiveis por padrao.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM mechanical_hub_auth;

-- A senha ja cumpriu seu papel; nao precisa continuar legivel na sessao.
SELECT set_config('mechanical_hub.auth_password', '', false);

-- ---------------------------------------------------------------------------
-- Verificacao
-- ---------------------------------------------------------------------------
-- Deve listar somente `profiles` (privilegio de tabela) e as seis colunas
-- liberadas de `users` (privilegio de coluna), todas com SELECT.
--
-- O GRANT por coluna nao aparece em role_table_grants — so em
-- role_column_grants. Por isso as duas visoes entram na consulta.
SELECT 'tabela' AS nivel, table_name, NULL AS column_name, privilege_type
  FROM information_schema.role_table_grants
 WHERE grantee = 'mechanical_hub_auth'
UNION ALL
SELECT 'coluna' AS nivel, table_name, column_name, privilege_type
  FROM information_schema.role_column_grants
 WHERE grantee = 'mechanical_hub_auth'
 ORDER BY nivel, table_name, column_name;

-- Falha explicita se a role acabou com qualquer privilegio de escrita.
DO $$
DECLARE
    escritas integer;
BEGIN
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
            'mechanical_hub_auth terminou com % privilegio(s) alem de SELECT.', escritas;
    END IF;

    RAISE NOTICE 'Verificacao OK: mechanical_hub_auth so tem SELECT.';
END
$$;
