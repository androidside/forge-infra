---
name: forge-debug
description: Debug and investigate Forge production issues - pipeline failures, ECS service logs, RDS database queries, and S3 artifact inspection. Use this skill whenever the user mentions a pipeline not completing, wants to check logs, needs to query the production database, wants to inspect S3 artifacts, or is troubleshooting any Forge service (content-forge celery worker, forge-nestjs API/worker). Also trigger when the user mentions a pipeline_run ID (UUID format), asks "what happened with...", or wants to check why something failed in production.
---

# Forge Production Debugger

You are helping debug production issues in the Forge platform deployed on AWS ECS Fargate.

## Architecture Overview

The Forge platform processes YouTube videos into short-form clips through an 11-step pipeline:

| Steps | Scope | Description |
|-------|-------|-------------|
| 1-4 | Global (per pipeline run) | download, transcribe, analyze, cut |
| 5-11 | Per-clip (parallel) | diarize, silence, face_track, crop, effects, subtitles, export |

**Services:**
- `forge-dev-celery` - Python Celery worker (content-forge) that runs the video pipeline. This is the primary debugging target.
- `forge-dev-api` - NestJS API server
- `forge-dev-worker` - NestJS BullMQ worker (triggers celery tasks, handles webhooks)
- `forge-dev-frontend` - React SPA

**Key resources:**
- ECS Cluster: `forge-dev-cluster`
- CloudWatch Log Group: `/ecs/forge-dev` (stream prefixes: `api`, `worker`, `frontend`, `celery`)
- RDS MySQL: `forge-dev-mysql.cpmvsvuj4pbf.us-east-1.rds.amazonaws.com`, database `forge`, user `forge_admin`
- S3 Bucket: `forge-dev-content-263618685979`
- Redis: used for BullMQ job queue and Celery broker
- Region: `us-east-1`

## Investigation Flow

When something goes wrong, follow this general approach. Adapt based on what the user tells you; you don't need to run every step every time.

### Step 1: Understand the problem

Ask the user what they're seeing. Common scenarios:
- "Pipeline X didn't complete" - need the pipeline_run ID (UUID)
- "Celery seems stuck" - check service health and logs
- "Something failed" - start with recent error logs

### Step 2: Check service health

```bash
# List running tasks for a service
aws ecs list-tasks --cluster forge-dev-cluster --service-name forge-dev-<service> --region us-east-1

# Describe tasks to check status, health, stop reasons
aws ecs describe-tasks --cluster forge-dev-cluster --tasks <task-arn> --region us-east-1

# Check recent ECS events (deployments, failures, restarts)
aws ecs describe-services --cluster forge-dev-cluster --services forge-dev-<service> --region us-east-1 --query 'services[0].events[:10]'
```

### Step 3: Check CloudWatch logs

The log group is `/ecs/forge-dev`. Each service uses its name as the stream prefix.

```bash
# Tail recent logs for a service (last 30 minutes)
aws logs tail /ecs/forge-dev --log-stream-name-prefix <service> --since 30m --region us-east-1

# Search for errors in celery logs
aws logs filter-events --log-group-name /ecs/forge-dev --log-stream-name-prefix celery --filter-pattern "ERROR" --start-time <epoch-ms> --region us-east-1

# Search for a specific pipeline run ID in logs
aws logs filter-events --log-group-name /ecs/forge-dev --log-stream-name-prefix celery --filter-pattern "<pipeline-run-id>" --start-time <epoch-ms> --region us-east-1
```

When searching by time, convert to epoch milliseconds: `date -d "2 hours ago" +%s%3N`

For `filter-events`, useful patterns:
- `"ERROR"` or `"Exception"` - find errors
- `"Traceback"` - Python stack traces
- `"<pipeline-run-id>"` - all logs for a specific run
- `"step_05"` or `"step_06"` etc. - logs for a specific pipeline step
- `"OOMKilled"` or `"oom"` - out of memory issues

### Step 4: Query the database

Use python3 with pymysql to query the production database. First retrieve credentials from Secrets Manager:

```bash
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id forge/db-credentials --region us-east-1 --query 'SecretString' --output text | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")
```

Then run queries using a python3 one-liner or short script:

```bash
python3 -c "
import pymysql, json
conn = pymysql.connect(host='forge-dev-mysql.cpmvsvuj4pbf.us-east-1.rds.amazonaws.com', user='forge_admin', password='$DB_PASSWORD', database='forge', port=3306)
cur = conn.cursor(pymysql.cursors.DictCursor)
cur.execute('<SQL QUERY HERE>')
for row in cur.fetchall(): print(json.dumps(row, default=str))
conn.close()
"
```

For convenience, you can also write a small temp script at `/tmp/forge_query.py` if the query is complex.

**Key tables and queries:**

```sql
-- Check a specific pipeline run
SELECT id, status, current_step, progress, youtube_url, error, created_at, updated_at
FROM pipeline_run WHERE id = '<uuid>';

-- Recent failed pipeline runs
SELECT id, status, current_step, error, created_at
FROM pipeline_run WHERE status = 'FAILED' ORDER BY created_at DESC LIMIT 10;

-- Recent pipeline runs (any status)
SELECT id, status, current_step, progress, youtube_url, created_at
FROM pipeline_run ORDER BY created_at DESC LIMIT 10;

-- Clips for a pipeline run (check which clips succeeded/failed)
SELECT id, status, clip_index, start_time, end_time, title, virality_score
FROM clip WHERE pipeline_run_id = '<uuid>' ORDER BY clip_index;

-- Check clip artifacts (S3 keys) to see what was produced
SELECT id, clip_index, status,
  JSON_EXTRACT(artifacts, '$.segment_video') as segment,
  JSON_EXTRACT(artifacts, '$.cropped_video') as cropped,
  JSON_EXTRACT(artifacts, '$.final_video') as final_video
FROM clip WHERE pipeline_run_id = '<uuid>';
```

**Pipeline run statuses:** QUEUED, PROCESSING, COMPLETED, FAILED, CANCELLED
**Pipeline steps (in order):** download, transcribe, analyze, cut, diarize, silence, face_track, crop, effects, subtitles, export

### Step 5: Inspect S3 artifacts

The S3 bucket stores all pipeline artifacts. Structure: `<pipeline_run_id>/<step_folder>/`

```bash
# List all folders for a pipeline run
aws s3 ls s3://forge-dev-content-263618685979/<pipeline-run-id>/

# List contents of a specific step
aws s3 ls s3://forge-dev-content-263618685979/<pipeline-run-id>/5-cropped/ --recursive

# Check what the last produced artifact folder is (to see where pipeline stopped)
aws s3 ls s3://forge-dev-content-263618685979/<pipeline-run-id>/
```

**Step folders:**
| Folder | Step | Contains |
|--------|------|----------|
| `1-sources/` | download | Source video and audio files |
| `2-transcripts/` | transcribe | Whisper transcription output |
| `3-analysis/` | analyze | LLM clip analysis/suggestions |
| `4-segments/` | cut | Cut video segments per clip |
| `5-cropped/` | crop | Cropped vertical videos |
| `5-cropped-effects/` | effects | Videos with visual effects |
| `5-cropped-subtitles/` | subtitles | Videos with burned-in subtitles |
| `6-final/` | export | Final exported clips |
| `7-publish/` | publish | Published/trimmed versions |

If a pipeline stops at step 5, the `6-final/` and `7-publish/` folders will be missing. This usually means the crop/effects/subtitles step failed for one or more clips.

To download an artifact for local inspection:
```bash
aws s3 cp s3://forge-dev-content-263618685979/<pipeline-run-id>/<path> /tmp/
```

### Step 6: Check Redis / BullMQ queue (if needed)

If you suspect jobs are stuck in the queue, check via the API service logs or ECS exec into the worker:

```bash
# Check if ECS exec is available
aws ecs execute-command --cluster forge-dev-cluster --task <task-id> --container <service> --command "/bin/sh" --interactive --region us-east-1
```

Note: ECS exec requires the Session Manager plugin. If it's not installed, you'll see an error about SessionManagerPlugin. In that case, fall back to CloudWatch logs.

## Common Failure Patterns

**Pipeline stuck at a step:**
- Check `current_step` in `pipeline_run` table
- Look at celery logs around the time the run was created
- Check S3 to see which step folders exist
- Common cause: celery task timed out (hard limit is 1 hour)

**Clips not completing:**
- Steps 5-11 run per-clip in parallel. One clip failing doesn't block others.
- Check individual clip statuses in the `clip` table
- Look for the specific clip index in celery logs

**Service not starting / crashing:**
- Check ECS events: `aws ecs describe-services --cluster forge-dev-cluster --services forge-dev-<service> --region us-east-1 --query 'services[0].events[:5]'`
- Look for OOM kills, health check failures, or image pull errors
- Check if the task definition has correct image tag

**Terraform deployment failures:**
- Check the GitHub Actions workflow logs
- Common: state lock contention, resource conflicts, permission issues

## Tips

- Always start by identifying WHEN the issue happened so you can scope your log searches
- Use `--since` with `aws logs tail` for recent issues, or `--start-time`/`--end-time` with `filter-events` for specific windows
- When the user gives you a pipeline run ID, check the database first (quick status overview), then logs, then S3
- The celery worker logs are verbose during processing; search for ERROR or the specific run ID to cut through noise
- If a pipeline run shows status PROCESSING but hasn't updated in a while, it's likely stuck or the celery task died silently
