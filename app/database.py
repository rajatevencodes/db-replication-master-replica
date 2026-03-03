import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

MASTER_URL = os.getenv("MASTER_DATABASE_URL", "postgresql://app:app@db-master:5432/appdb")
REPLICA_URL = os.getenv("REPLICA_DATABASE_URL", "postgresql://app:app@db-replica:5432/appdb")

master_engine = create_engine(MASTER_URL)
replica_engine = create_engine(REPLICA_URL)

MasterSession = sessionmaker(bind=master_engine)
ReplicaSession = sessionmaker(bind=replica_engine)


def get_master_db():
    db = MasterSession()
    try:
        yield db
    finally:
        db.close()


def get_replica_db():
    db = ReplicaSession()
    try:
        yield db
    finally:
        db.close()
