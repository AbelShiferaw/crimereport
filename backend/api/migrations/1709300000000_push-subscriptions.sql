-- Up Migration

CREATE TABLE push_subscriptions (
    device_id    VARCHAR(64)  PRIMARY KEY,
    fcm_token    VARCHAR(500) NOT NULL,
    platform     VARCHAR(10)  NOT NULL CHECK (platform IN ('ios', 'android')),
    endpoint_arn VARCHAR(500),
    location     geography(Point, 4326),
    radius       INTEGER      NOT NULL DEFAULT 10000,
    types        TEXT[]       DEFAULT NULL,
    enabled      BOOLEAN      NOT NULL DEFAULT true,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_push_subscriptions_location
    ON push_subscriptions USING GIST (location);

-- Down Migration

DROP INDEX IF EXISTS idx_push_subscriptions_location;
DROP TABLE IF EXISTS push_subscriptions;
