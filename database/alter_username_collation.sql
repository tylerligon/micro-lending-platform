-- One-time update for the existing development database; not a fresh-build step.
-- Check for conflicting names under this collation before running this statement.
-- Keep the existing column size, NOT NULL rule, and unique index.
ALTER TABLE `User`
    MODIFY LoginName VARCHAR(80) COLLATE utf8mb4_0900_ai_ci NOT NULL;
