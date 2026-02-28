-- Up Migration

ALTER TABLE comments ADD COLUMN flag_count INTEGER NOT NULL DEFAULT 0;

CREATE TABLE comment_flags (
    comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comment_id, device_id)
);

-- Down Migration

DROP TABLE IF EXISTS comment_flags;
ALTER TABLE comments DROP COLUMN IF EXISTS flag_count;
