# Aerospike Data Masking Demo

Demonstrates Aerospike Enterprise's dynamic data masking feature with RBAC.

## Prerequisites

- Docker & Docker Compose

## Quick Start

```bash
# Run the interactive demo
./demo.sh
```

## Manual Setup

```bash
# Start the server
docker compose up -d

# Connect as admin
docker run --rm -it --network datamasking_aerospike-qs \
  aerospike/aerospike-server-enterprise:8.1.1.0 \
  asadm -h aerospike-masking -p 3000 -U admin -P admin
```

## Users

| User | Password | Access |
|------|----------|--------|
| `app_service` | `SecureApp123!` | Unmasked data (read/write) |
| `analyst_1` | `Analyst456!` | Masked data (read-only) |
| `masking_admin` | `DBA789!` | Masking rules admin |
| `admin` | `admin` | System admin |

## Masking Rules

| Bin | Rule | Example |
|-----|------|---------|
| `ssn` | Redact first 7 chars | `123-45-6789` → `*******6789` |
| `email` | Constant replacement | → `redacted@example.com` |
| `notes` | Constant replacement | → `[REDACTED]` |

## Cleanup

```bash
docker compose down -v
```

## Files

- `demo.sh` - Interactive demo script
- `aerospike.conf` - Server config with security enabled
- `docker-compose.yml` - Container orchestration
- `Dockerfile` - Custom image with config baked in

## Learn More

- [How to keep data masking from breaking in production](https://aerospike.com/blog/understanding-data-masking) - Deep dive into static vs dynamic masking, techniques, and Aerospike's native DDM
