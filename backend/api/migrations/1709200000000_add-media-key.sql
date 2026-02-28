-- Up Migration

ALTER TABLE media ADD COLUMN media_key VARCHAR(500);
ALTER TABLE media ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'pending';

CREATE INDEX idx_media_media_key ON media(media_key);
CREATE INDEX idx_media_status ON media(status);

-- Down Migration

DROP INDEX IF EXISTS idx_media_status;
DROP INDEX IF EXISTS idx_media_media_key;
ALTER TABLE media DROP COLUMN IF EXISTS status;
ALTER TABLE media DROP COLUMN IF EXISTS media_key;
