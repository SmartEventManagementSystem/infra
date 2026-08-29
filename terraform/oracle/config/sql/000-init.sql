CREATE
EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE
EXTENSION IF NOT EXISTS "postgis";
CREATE
EXTENSION IF NOT EXISTS "plpgsql";

CREATE
OR REPLACE FUNCTION insert_updated_at() RETURNS trigger
  LANGUAGE plpgsql
AS
$$
BEGIN
  NEW.updated_at
= NOW();
RETURN NEW;
END
$$;

CREATE FUNCTION trigger_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF
NEW IS DISTINCT FROM OLD AND NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at
  THEN
    NEW.updated_at = NOW();
END IF;
RETURN NEW;
END
$$;
