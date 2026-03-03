# DB Master-Replica

A minimal FastAPI app demonstrating PostgreSQL master-replica setup with synchronous streaming replication.

## Architecture

```mermaid
flowchart TB
    Client([Client - You])

    Client -->|"POST / PUT / DELETE (write)"| API
    Client -->|"GET (read)"| API

    subgraph Docker["Docker Compose (all 3 run inside Docker)"]
        API["FastAPI :8000\n(our Python app)"]

        API -->|"write queries go here"| Master[("Master DB :5432\n(single source of truth)")]
        API -->|"read queries go here"| Replica[("Replica DB :5433\n(read-only copy)")]

        Master -->|"sends every change\n(via WAL log)"| Replica
        Replica -.->|"confirms: got it"| Master
    end
```

## How Replication Works Step by Step

```mermaid
sequenceDiagram
    participant C as Client (you)
    participant A as FastAPI (connects as user: app)
    participant M as Master DB (appdb)
    participant R as Replica DB (appdb)

    Note over C,R: WRITING - client creates a new item

    C->>A: POST /items {"title": "hello"}
    A->>M: INSERT INTO items (app user writes to appdb)
    Note right of M: Master writes the data AND<br/>logs it in the WAL (change diary)
    M->>R: replicator user sends the WAL entry
    R-->>M: "got it, I applied the change"
    Note right of R: Only after replica confirms,<br/>master tells the app "done"
    M-->>A: commit successful
    A-->>C: 201 Created

    Note over C,R: READING - client reads all items

    C->>A: GET /items
    A->>R: SELECT * FROM items (app user reads from appdb)
    Note right of R: Replica has the data because<br/>replicator synced it above
    R-->>A: returns the rows
    A-->>C: 200 OK [{"title": "hello"}]
```

## How the Replica Starts Up

```mermaid
sequenceDiagram
    participant M as Master DB
    participant R as Replica DB

    Note over M: Master starts first,<br/>runs init-master.sh:<br/>creates 2 users + 1 database:<br/>• replicator (for syncing data)<br/>• app (for FastAPI to query)<br/>• appdb (our database)

    Note over R: Replica starts after master is healthy

    R->>M: replicator user runs pg_basebackup (full copy of all data)
    M-->>R: here's everything (appdb, users, tables — all of it)

    Note over R: Replica now has identical copy:<br/>same appdb, same items table, same data

    R->>M: replicator opens a streaming connection
    Note over M,R: From now on, every change on master<br/>is sent to replica via replicator in real-time

    Note over R: Replica is READ-ONLY.<br/>FastAPI connects as app user to read from appdb.
```

## Who Does What (Users & Database)

| Name | What is it | Purpose |
|------|-----------|---------|
| `app` | PostgreSQL user | FastAPI uses this to connect and run queries (SELECT, INSERT, etc.) |
| `replicator` | PostgreSQL user | Replica uses this to copy and stream data from master |
| `appdb` | Database | The actual database where the `items` table lives |

## Project Structure

```
├── docker-compose.yml     # 3 services: master, replica, api
├── Dockerfile             # FastAPI container
├── Makefile               # up / down / clean
├── pyproject.toml         # python dependencies (uv)
├── app/
│   ├── main.py            # endpoints (GET→replica, writes→master)
│   ├── database.py        # two db connections
│   ├── models.py          # Item table
│   └── schemas.py         # request/response models
└── db/
    ├── init-master.sh     # creates users, enables replication
    └── init-replica.sh    # clones master, starts as read-only copy
```

## Quick Start

```bash
make up       # start everything
make down     # stop containers
make clean    # stop + remove volumes and images
```

## pgAdmin (View Your Databases in Browser)

After `make up`, open [http://localhost:5050](http://localhost:5050)

**Login:** `admin@admin.com` / `admin`

Then add two servers: **Right-click "Servers" → Register → Server**

### Master

| Tab | Field | Value |
|-----|-------|-------|
| General | Name | `Master` |
| Connection | Host | `db-master` |
| Connection | Port | `5432` |
| Connection | Username | `app` |
| Connection | Password | `app` |
| Connection | Maintenance database | `appdb` |

### Replica

| Tab | Field | Value |
|-----|-------|-------|
| General | Name | `Replica` |
| Connection | Host | `db-replica` |
| Connection | Port | `5432` |
| Connection | Username | `app` |
| Connection | Password | `app` |
| Connection | Maintenance database | `appdb` |

### Why port 5432 for both?

```mermaid
flowchart TB
    subgraph mac["🖥️ Your Mac (outside Docker)"]
        You([You])
    end

    subgraph docker["🐳 Docker Network — each container has its own IP"]
        pgAdmin["pgAdmin\n172.x.x.2"]
        Master[("Master DB\n172.x.x.3\n:5432")]
        Replica[("Replica DB\n172.x.x.4\n:5432")]
    end

    You -->|"localhost:5432"| Master
    You -->|"localhost:5433 ⟵ remapped"| Replica

    pgAdmin -.->|"db-master:5432"| Master
    pgAdmin -.->|"db-replica:5432"| Replica
```

> Each container has its **own IP** inside Docker — so both databases can run on `:5432` without conflict.
> On your Mac, `localhost` is a **single IP**, so the replica is remapped to `:5433` to avoid clashing with the master.
> pgAdmin lives **inside** Docker, so it talks to both on `:5432` directly — no remapping needed.

To view data: **Server → appdb → Schemas → public → Tables → items → Right-click → View/Edit Data**


