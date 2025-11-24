-- Add missing mt5_password_encrypted column to bot_configs table
ALTER TABLE bot_configs
ADD COLUMN IF NOT EXISTS mt5_password_encrypted VARCHAR;

-- Display success message
SELECT 'Column added successfully!' AS status;
