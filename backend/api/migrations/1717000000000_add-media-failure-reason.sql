-- Up Migration

-- Tracks the cause of media-pipeline failures so the API can distinguish
-- content moderation rejections (`flagged_content`) from AWS-side
-- processing errors (`processing_error`, `unsupported_format`). Nullable
-- and additive so existing rows and code paths stay valid.
ALTER TABLE media ADD COLUMN failure_reason VARCHAR(50);

-- Down Migration

ALTER TABLE media DROP COLUMN IF EXISTS failure_reason;
