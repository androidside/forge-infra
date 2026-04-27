# Architecture

## Overview

The Forge platform runs on AWS using ECS Fargate for all compute, with RDS MySQL and ElastiCache Redis as managed data stores. S3 replaces MinIO for object storage. All services run in private subnets behind an ALB.

For a more detailed component view including external systems (Google OAuth, YouTube, social platforms) and per-arrow protocol/queue annotations, see [`forge-architecture.excalidraw`](./forge-architecture.excalidraw). Open it on [excalidraw.com](https://excalidraw.com) (drag-and-drop the file) or with the VS Code Excalidraw extension.

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

1. **User** hits `app.{domain}` → ALB → frontend (nginx serves React SPA)
2. **React app** calls `api.{domain}` → ALB → API (NestJS, `APP_TYPE=api`)
3. **API** receives video URL → writes to DB → submits Celery task to Redis (Celery broker)
4. **Celery worker** (`forge-celery`, content-forge) picks up the task → downloads via yt-dlp → runs the 11-step pipeline → writes artifacts to S3 → publishes step events to Redis pub/sub on channel `pipeline:{job_id}`
5. **API** subscribes to Redis pub/sub on the same channel → streams progress to the frontend over SSE
6. **API** receives a publish request → enqueues a BullMQ job on the `social-publish` queue → **NestJS Worker** (`forge-worker`, `APP_TYPE=worker`) consumes it and publishes to social platforms
7. **NestJS Worker cron jobs** also submit work directly to the Celery queue or BullMQ:
   - `youtube-scanner` (every 30 min) — auto-discovers new videos and submits Celery pipeline tasks
   - `auto-publish` (every 15 min) — promotes scheduled clips to the publish queue
   - `scheduled-post-recovery` (every 1 min) — re-enqueues stuck `social-publish` jobs
   - `platform-status` (every 5 min) — refreshes social OAuth tokens

There are two distinct queues, both backed by the same Redis instance:

| Queue | Producer(s) | Consumer | Library |
|-------|-------------|----------|---------|
| Celery broker (`video pipeline`) | API, Worker (cron) | Content-Forge Celery | celery (Python) |
| BullMQ (`social-publish`) | API, Worker (cron) | NestJS Worker | `@nestjs/bullmq` |

Redis is also used as a **pub/sub bus** (channel `pipeline:{job_id}`) for live progress events from Content-Forge to the API.

## S3 Compatibility

The NestJS `StorageService` uses the `minio` npm package which is S3-compatible. In production:

| Config | Local (MinIO) | Production (S3) |
|--------|---------------|-----------------|
| `MINIO_ENDPOINT` | `localhost:9000` | `s3.us-east-1.amazonaws.com` |
| `MINIO_SECURE` | `false` | `true` |
| `MINIO_ACCESS_KEY` | `minioadmin` | (empty - uses IAM role) |
| `MINIO_SECRET_KEY` | `minioadmin` | (empty - uses IAM role) |

The ECS task role has S3 permissions, so the MinIO client authenticates via the instance metadata service automatically.

## Public Exposure / Attack Surface

Only two services are reachable from the internet, both via the ALB on HTTPS:

| Hostname | ECS Service | Container Port | Purpose |
|----------|-------------|----------------|---------|
| `app.{domain}` | `frontend` | 8080 | React SPA (static assets via nginx) |
| `api.{domain}` | `api` | 3000 | NestJS REST + SSE endpoints |

Everything else is in private subnets with no public IP and security-group ingress restricted to peer services:

| Resource | Internet ingress | Allowed sources |
|----------|------------------|-----------------|
| NestJS Worker | None — `enable_load_balancer = false`, no ALB target group | n/a (no inbound traffic) |
| Content-Forge Celery | None — `enable_load_balancer = false`, no ALB target group | n/a (no inbound traffic) |
| RDS MySQL | None — `publicly_accessible = false`, private subnets | API SG, Worker SG, Celery SG (port 3306) |
| ElastiCache Redis | None — private subnets | API SG, Worker SG, Celery SG (port 6379) |
| S3 bucket | None — `block_public_acls`, `block_public_policy`, `restrict_public_buckets` all `true` | ECS task IAM roles only; presigned URLs for browser uploads/downloads |

ECS tasks run with `assign_public_ip = false` in private subnets. Outbound internet (for ECR pulls, Google OAuth, YouTube, social-platform APIs) goes through the NAT Gateway.

In short: any attempt to reach the worker, Celery, database, Redis, or S3 from outside the VPC has to pass through the API first (or, for static assets, the frontend). The realistic external attack surface is the API endpoints, the SPA, and the Google OAuth login redirect.
