-- Table users
CREATE TABLE users
(
  id              UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
  
  -- identity
  username        TEXT UNIQUE NOT NULL,               -- display name (unique handle)
  email           TEXT UNIQUE,                        -- login/notification email
  phone_number    TEXT UNIQUE,                        -- optional, for OTP/KYC
  password   TEXT NOT NULL,                      -- hashed via bcrypt/argon2
  
  -- auth & status
  status          TEXT NOT NULL DEFAULT 'UNVERIFIED', -- UNVERIFIED | ACTIVE | SUSPENDED | BANNED
  role            TEXT NOT NULL DEFAULT 'USER',       -- USER | ADMIN | MODERATOR | SPONSOR etc.
  email_verified  BOOLEAN DEFAULT FALSE,
  phone_verified  BOOLEAN DEFAULT FALSE,
  last_login_at   TIMESTAMPTZ,                        -- last successful login
  
  -- audit & lifecycle
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ,                        -- soft delete
  deactivated_at  TIMESTAMPTZ                         -- explicit deactivation (different from delete)
);

CREATE TRIGGER trigger_users_updated_at
  BEFORE UPDATE
  ON users
  FOR EACH ROW
  EXECUTE FUNCTION trigger_updated_at();

-- Indexes
CREATE UNIQUE INDEX unique_idx_users_by_username
  ON users (username) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX unique_idx_users_by_email
  ON users (email) WHERE (deleted_at IS NULL);

-- Auth schema: sessions table

CREATE TABLE IF NOT EXISTS sessions (
  id           UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL,
  token        TEXT NOT NULL UNIQUE,
  user_agent   TEXT,
  ip_address   TEXT,
  revoked      BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ,
  deleted_at   TIMESTAMPTZ
);

CREATE TRIGGER trigger_sessions_updated_at
  BEFORE UPDATE
  ON sessions
  FOR EACH ROW
  EXECUTE FUNCTION trigger_updated_at();

CREATE INDEX IF NOT EXISTS idx_sessions_by_user_id ON sessions (user_id) WHERE (deleted_at IS NULL);

CREATE TABLE jobs
(
  id           UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4(),
  type         VARCHAR(255) NOT NULL,
  status       VARCHAR(50)  NOT NULL DEFAULT 'pending',
  priority     INTEGER      NOT NULL DEFAULT 1,
  payload      JSONB        NOT NULL DEFAULT '{}',
  attempts     INTEGER      NOT NULL DEFAULT 0,
  max_attempts INTEGER      NOT NULL DEFAULT 3,
  scheduled_at TIMESTAMPTZ,
  started_at   TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at   TIMESTAMPTZ           DEFAULT now(),
  updated_at   TIMESTAMPTZ,
  deleted_at   TIMESTAMPTZ,
  error        TEXT
);

CREATE TRIGGER trigger_jobs_updated_at
  BEFORE UPDATE
  ON jobs
  FOR EACH ROW
  EXECUTE FUNCTION trigger_updated_at();

CREATE INDEX idx_jobs_status ON jobs(status) WHERE deleted_at IS NULL;
