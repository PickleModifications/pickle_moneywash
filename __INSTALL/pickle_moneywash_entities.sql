-- Placeable entities storage for pickle_moneywash
-- Import this into your database (same DB as your framework).
--
-- This table is intentionally generic so it can support multiple future entity types,
-- not just money counters.

CREATE TABLE IF NOT EXISTS `pickle_moneywash_entities` (
  `id` VARCHAR(64) NOT NULL,
  `type` VARCHAR(64) NOT NULL,
  `coords` LONGTEXT NOT NULL,
  `heading` DOUBLE NOT NULL DEFAULT 0,
  `data` LONGTEXT NULL,
  `created_by` VARCHAR(128) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pickle_moneywash_entities_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

