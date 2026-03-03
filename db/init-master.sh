#!/bin/bash
set -e

# ============================================
# MASTER DATABASE SETUP
# This script runs ONCE when the master DB
# starts for the first time.
# ============================================

# --- STEP 1: Create users and database ---
# Think of this like creating accounts:
#   - "replicator" = an account the replica uses to copy data from master
#   - "app"        = an account our FastAPI app uses to read/write data
#   - "appdb"      = the actual database where our items table will live
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'replicator';
    CREATE USER app WITH ENCRYPTED PASSWORD 'app';
    CREATE DATABASE appdb OWNER app;
EOSQL

# --- STEP 2: Allow connections from outside ---
# By default, PostgreSQL blocks everyone. These lines open the door:
#   - Let "replicator" connect from any IP (so the replica container can reach us)
#   - Let "app" connect from any IP (so the FastAPI container can reach us)
echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
echo "host all app 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"

# --- STEP 3: Turn on replication ---
# Without these settings, the master won't share any data with replicas.
cat >> "$PGDATA/postgresql.conf" <<EOF
wal_level = replica
max_wal_senders = 3
synchronous_standby_names = 'replica'
synchronous_commit = on
EOF
# wal_level = replica                  → keep a log of every change (needed for replication)
# max_wal_senders = 3                  → up to 3 replicas can connect at once
# synchronous_standby_names = 'replica'→ the replica named "replica" must confirm every write
# synchronous_commit = on              → don't tell the app "write done" until replica confirms
