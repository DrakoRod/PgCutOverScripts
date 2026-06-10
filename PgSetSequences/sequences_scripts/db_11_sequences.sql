-- =====================================================
-- Database: db_11
-- Host: localhost:5444
-- User: admin
-- Generated: 2026-06-10 11:21:39
-- Description: Script to restore sequence last values
-- =====================================================
-- IMPORTANT: Run this script on the target database
-- to restore the original sequence positions
-- =====================================================

BEGIN;

-- Sequence: public.table1_id_seq
-- Last value: 3 (start: , increment: 1)
SELECT setval('public.table1_id_seq', 3, true);

-- Sequence: public.table2_id_seq
-- Last value: 3 (start: , increment: 1)
SELECT setval('public.table2_id_seq', 3, true);


COMMIT;

-- =====================================================
-- Verification query (optional):
-- SELECT schemaname, sequencename, last_value 
-- FROM pg_sequences 
-- WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
-- ORDER BY schemaname, sequencename;
-- =====================================================
