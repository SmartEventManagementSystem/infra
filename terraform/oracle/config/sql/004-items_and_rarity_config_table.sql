-- =====================================================================
-- 004-items_and_rarity_config_table.sql
-- Schema for rarity configs and items
-- =====================================================================

-- =====================
-- 1. Rarity Configs
-- =====================
CREATE TABLE rarity_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(10) UNIQUE NOT NULL,
    label VARCHAR(50) NOT NULL,
    rank SMALLINT NOT NULL,
    color_hex VARCHAR(10),
    drop_weight INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_rarity_configs_rank ON rarity_configs (rank)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trigger_rarity_configs_updated_at
  BEFORE UPDATE ON rarity_configs
  FOR EACH ROW EXECUTE FUNCTION trigger_updated_at();


-- =====================
-- 2. Items
-- =====================
CREATE TABLE items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    description TEXT,
    rarity_config_id UUID NOT NULL,
    image_url TEXT,
    country_id UUID,
    location_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_items_rarity_config_id ON items (rarity_config_id)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_items_name ON items (name)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trigger_items_updated_at
  BEFORE UPDATE ON items
  FOR EACH ROW EXECUTE FUNCTION trigger_updated_at();
