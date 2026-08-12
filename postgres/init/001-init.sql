-- =============================================================================
-- ACR Platform — local PostgreSQL bootstrap
-- =============================================================================
-- Runs automatically on first container start (postgres official image
-- executes every *.sql / *.sh file in /docker-entrypoint-initdb.d/ once,
-- only when the data directory is empty).

-- pg_trgm: trigram-based fuzzy text matching, used for:
--   - Automatic version detection comparing author/title/abstract (SOW §3.3)
--   - Automatic unbiasing / conflict-of-interest fuzzy name matching (SOW §3.4)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- uuid-ossp: UUID generation, commonly used for public-facing IDs
-- (e.g. tokenised invitation links per SOW §3.5) instead of leaking
-- sequential integer IDs.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- unaccent: strips accents for more robust name matching across
-- international reviewer names/affiliations.
CREATE EXTENSION IF NOT EXISTS unaccent;
