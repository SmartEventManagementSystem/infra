-- Table user_balances
CREATE TABLE
    user_balances (
        id UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4 (),
        user_id UUID NOT NULL,
        balance BIGINT NOT NULL DEFAULT 0,
        currency VARCHAR(20) NOT NULL, -- "COIN", "SPIN", etc.
        -- audit & lifecycle
        created_at TIMESTAMPTZ NOT NULL DEFAULT now (),
        updated_at TIMESTAMPTZ,
        deleted_at TIMESTAMPTZ -- soft delete
    );

CREATE TRIGGER trigger_user_balances_updated_at BEFORE
UPDATE ON user_balances FOR EACH ROW EXECUTE FUNCTION trigger_updated_at ();

CREATE INDEX idx_user_balances_by_user_id ON user_balances USING btree (user_id)
WHERE
    deleted_at IS NULL;

-- Table user_balance_transactions
CREATE TABLE
    user_balance_transactions (
        id UUID PRIMARY KEY NOT NULL DEFAULT uuid_generate_v4 (),
        user_id UUID NOT NULL,
        amount BIGINT NOT NULL,
        currency VARCHAR(20) NOT NULL,
        type VARCHAR(50) NOT NULL, -- e.g. DAILY_REWARD, AD_WATCH, PURCHASE, SPIN_USE, etc.
        source VARCHAR(50) NOT NULL, -- e.g. 'DAILY_LOGIN', 'VIDEO_AD', 'STORE_PURCHASE'
        status VARCHAR(20) NOT NULL, -- "PENDING", "COMPLETED", "FAILED", etc.
        -- audit & lifecycle
        created_at TIMESTAMPTZ NOT NULL DEFAULT now (),
        updated_at TIMESTAMPTZ,
        deleted_at TIMESTAMPTZ -- soft delete
    );

CREATE TRIGGER trigger_user_balance_transactions_updated_at BEFORE
UPDATE ON user_balance_transactions FOR EACH ROW EXECUTE FUNCTION trigger_updated_at ();

CREATE INDEX idx_user_balance_transactions_by_user_id ON user_balance_transactions USING btree (user_id)
WHERE
    deleted_at IS NULL;

CREATE INDEX idx_user_balance_transactions_by_currency ON user_balance_transactions USING btree (currency)
WHERE
    deleted_at IS NULL;

CREATE INDEX idx_user_balance_transactions_by_user_id_and_currency ON user_balance_transactions USING btree (user_id, currency)
WHERE
    deleted_at IS NULL;

CREATE INDEX idx_user_balance_transactions_by_user_id_and_currency_and_type ON user_balance_transactions USING btree (user_id, currency, type)
WHERE
    deleted_at IS NULL;