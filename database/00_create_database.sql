-- Create only our local development database. No existing database is deleted.
-- If this name already exists, MySQL stops with an error.
CREATE DATABASE micro_lending_dev
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
