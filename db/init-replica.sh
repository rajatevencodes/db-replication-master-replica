#!/bin/bash
set -e

# ============================================
# REPLICA DATABASE SETUP
# This script runs every time the replica
# container starts. It clones data from the
# master and then follows it in real-time.
# ============================================

# --- STEP 1: Already set up? Just start. ---
# If we already copied data before (container restart), skip setup and start postgres.
if [ -f "$PGDATA/PG_VERSION" ]; then
    exec gosu postgres postgres
fi

# --- STEP 2: Wait for master to be ready ---
# The replica can't copy anything if the master isn't running yet.
# Keep checking every second until the master responds.
until pg_isready -h db-master -U replicator; do
    echo "Waiting for master..."
    sleep 1
done

# --- STEP 3: Clone everything from master ---
# This is like making a full photocopy of the master's entire database.
# After this, the replica has an identical copy of all the data.
rm -rf "$PGDATA"/*
PGPASSWORD=replicator pg_basebackup -h db-master -U replicator -D "$PGDATA" -Fp -Xs -R -P
#   -Fp = copy files as-is (plain format)
#   -Xs = also stream the change log during copy
#   -R  = automatically configure this as a replica
#   -P  = show progress while copying

# --- STEP 4: Tell the replica where the master is ---
# This is the address the replica will keep pulling new changes from.
# "application_name=replica" must match the master's synchronous_standby_names setting.
cat >> "$PGDATA/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=db-master port=5432 user=replicator password=replicator application_name=replica'
EOF

# --- STEP 5: Hand ownership to postgres user and start ---
# PostgreSQL refuses to run as root for security reasons.
# chown gives the data directory to the "postgres" user.
# gosu switches from root to "postgres" user before starting.
chown -R postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"
exec gosu postgres postgres
