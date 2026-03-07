# Architecture

## Overview

The Forge platform runs on AWS using ECS Fargate for all compute, with RDS MySQL and ElastiCache Redis as managed data stores. S3 replaces MinIO for object storage. All services run in private subnets behind an ALB.

## Network Topology

```
                         Internet
                            │
                      ┌─────▼─────┐
                      │  Route 53 │
                      │   DNS     │
                      └─────┬─────┘
                            │
                    ┌───────▼────────┐
                    │  ACM Wildcard  │
                    │  Certificate   │
                    └───────┬────────┘
                            │
              ┌─────────────▼──────────────┐
              │   Application Load Balancer │
              │   (Public Subnets)          │
              │   HTTP→HTTPS redirect       │
              └──────┬──────────────┬───────┘
                     │              │
          ┌──────────▼───┐   ┌─────▼──────────┐
          │ app.domain   │   │ api.domain     │
          │ ┌──────────┐ │   │ ┌────────────┐ │
          │ │ frontend │ │   │ │   API      │ │
          │ │ (nginx)  │ │   │ │ (NestJS)   │ │
          │ │ port 80  │ │   │ │ port 3000  │ │
          │ └──────────┘ │   │ └────────────┘ │
          └──────────────┘   └───────┬────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
     ┌────────▼────────┐   ┌────────▼────────┐   ┌────────▼────────┐
     │   RDS MySQL     │   │ ElastiCache     │   │   S3 Bucket     │
     │   8.0           │   │ Redis 7.0       │   │   (content)     │
     │   db.t4g.micro  │   │ cache.t4g.micro │   │                 │
     └─────────────────┘   └────────┬────────┘   └─────────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │                               │
           ┌───────▼────────┐             ┌────────▼────────┐
           │ NestJS Worker  │             │ Celery Worker   │
           │ (BullMQ)       │             │ (content-forge) │
           │ No ALB         │             │ No ALB          │
           └────────────────┘             └─────────────────┘
```

## Subnets

| Subnet Type | CIDR | Purpose |
|-------------|------|---------|
| Public 1 (us-east-1a) | 10.0.1.0/24 | ALB, NAT Gateway |
| Public 2 (us-east-1b) | 10.0.2.0/24 | ALB (2 AZ requirement) |
| Private 1 (us-east-1a) | 10.0.10.0/24 | ECS tasks, RDS, Redis |
| Private 2 (us-east-1b) | 10.0.11.0/24 | RDS standby (multi-AZ), ECS |

## ECS Services

| Service | Image Source | Port | ALB | CPU | Memory | Purpose |
|---------|-------------|------|-----|-----|--------|---------|
| `frontend` | forge-frontend | 80 | app.domain | 256 | 512 | React SPA via nginx |
| `api` | forge-nestjs | 3000 | api.domain | 256 | 512 | NestJS REST API (APP_TYPE=api) |
| `worker` | forge-nestjs | - | No | 256 | 512 | BullMQ processor (APP_TYPE=worker) |
| `celery` | content-forge | - | No | 512 | 1024 | Video pipeline Celery worker |

## Security Groups

```
ALB SG ──────────► Frontend SG (port 80)
                 ► API SG (port 3000)

API SG ──────────► RDS SG (port 3306)
                 ► Redis SG (port 6379)

Worker SG ───────► RDS SG (port 3306)
                 ► Redis SG (port 6379)

Celery SG ───────► Redis SG (port 6379)

All SGs ─────────► 0.0.0.0/0 (egress, for ECR pull, S3, external APIs)
```

## Data Flow

1. **User** hits `app.domain.com` → ALB → frontend (nginx serves React SPA)
2. **React app** calls `api.domain.com` → ALB → API (NestJS)
3. **API** receives video URL → writes to DB → pushes Celery task to Redis
4. **Celery worker** picks up task → processes video → writes clips to S3 → publishes progress to Redis pub/sub
5. **API** receives SSE subscription → listens on Redis pub/sub → streams progress to frontend
6. **API** receives publish request → enqueues BullMQ job → worker publishes to social platforms

## S3 Compatibility

The NestJS `StorageService` uses the `minio` npm package which is S3-compatible. In production:

| Config | Local (MinIO) | Production (S3) |
|--------|---------------|-----------------|
| `MINIO_ENDPOINT` | `localhost:9000` | `s3.us-east-1.amazonaws.com` |
| `MINIO_SECURE` | `false` | `true` |
| `MINIO_ACCESS_KEY` | `minioadmin` | (empty - uses IAM role) |
| `MINIO_SECRET_KEY` | `minioadmin` | (empty - uses IAM role) |

The ECS task role has S3 permissions, so the MinIO client authenticates via the instance metadata service automatically.
