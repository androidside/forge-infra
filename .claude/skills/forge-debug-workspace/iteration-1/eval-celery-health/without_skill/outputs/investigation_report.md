# Celery Worker Health Investigation Report

**Date:** 2026-03-16
**Service:** forge-dev-celery
**Cluster:** forge-dev-cluster (us-east-1)

## Summary

The celery worker container is **running but idle**. It is not stuck or crashed; it is simply waiting for new tasks. However, there is a **recurring FFmpeg stall bug** that causes clip 3 (vertical format) to fail during the subtitles step (step_10) on every pipeline run observed.

## Service Status

| Metric | Value |
|--------|-------|
| ECS Service Status | ACTIVE |
| Desired Count | 1 |
| Running Count | 1 |
| Task Status | RUNNING |
| Task Started | 2026-03-15 23:15:30 (about 17 hours ago) |
| Last Deployment | 2026-03-15 23:11:25 (steady state reached at 23:17) |
| Health Status | UNKNOWN (no health check configured for non-ALB service) |
| Failed Tasks | 0 (ECS level) |

## Resource Utilization

**Current (last hour):** CPU avg ~0.02%, Memory avg ~2.4% (of 16GB). The worker is essentially idle.

**Last 24 hours (hourly CPU):**
- Active processing periods: 15:41-20:41 yesterday (up to 72% avg, 99% peak), 22:41-23:41 yesterday (27% avg), 12:41-13:41 today (35% avg)
- Idle since ~13:42 today: CPU dropped to 0.02%

The worker has 4 vCPU and 16GB RAM allocated, which is more than sufficient. Memory utilization has been steady at 2.4%, indicating no memory leak.

## Configuration

- **Image:** forge-worker:latest
- **CPU/Memory:** 4096 CPU units (4 vCPU) / 16384 MB (16 GB)
- **Ephemeral Storage:** 40 GB
- **Concurrency:** 2 (prefork)
- **FFMPEG_THREADS:** 1
- **Queue:** "video"
- **Celery version:** 5.5.3

## Logs Analysis

### Current Task (84c14003, started 2026-03-15 23:15)

The worker started successfully, connected to Redis, and has been processing tasks. The last log entry is from **2026-03-16 13:41:16**, about 9 hours ago. After that, the worker returned to idle (no tasks in queue).

### Recurring Error: FFmpeg Stall on Vertical Encoding

The same error has occurred on **both pipeline runs observed** in this task's lifetime:

1. **Run 019cf54e** (Mar 15 ~23:21): `step_10_subtitles` failed for clip 3 with `FFmpegError: FFmpeg stalled (no output for 120s) encoding final_vertical_3.mp4`
2. **Run 019cf84c** (Mar 16 ~13:17): Same error on clip 3, same file `final_vertical_3.mp4`

In both cases, horizontal and letterbox encodes completed successfully, but the **vertical (1080x1920) encode for clip 3 specifically** stalls and times out after 120 seconds.

Other clips (clip 0, 1, 2) completed all formats successfully. This suggests a content-specific issue with clip 3's vertical encoding, possibly related to the FFmpeg filter chain for that particular clip's time segment combined with the vertical resolution.

### Previous Task (6656695f, Mar 15 19:41-21:24)

This task also had errors, including a **MySQL IntegrityError** on `step_04_cut`: `Cannot add or update a child row: a foreign key constraint fails (forge.clip, CONSTRAINT clip_pipeline_run_id_foreign)`. This is a separate database-level issue where clip records reference a pipeline_run that does not exist yet or has been deleted.

## Root Cause Assessment

The celery worker is **not slow or stuck**. It is healthy and idle, waiting for new tasks. The perception of it being slow or stuck likely stems from:

1. **FFmpeg stall failures on vertical encoding of clip 3** - causing partial pipeline failures where some clips succeed but clip 3's vertical format consistently times out
2. **No new tasks in the queue** - the worker has been idle for ~9 hours since the last job completed/failed

## Recommendations

1. **FFmpeg vertical encoding stall (high priority):** The `final_vertical_3.mp4` encoding consistently stalls. This is happening in `ffmpeg_utils.py:949` (`apply_combined_filters`). Possible causes:
   - FFmpeg deadlock when encoding vertical format with complex filter chains and `FFMPEG_THREADS=1`
   - Consider increasing `FFMPEG_THREADS` from 1 to 2 since the worker has 4 vCPUs
   - Consider increasing the `FFMPEG_STALL_TIMEOUT` from 120s, or adding retry logic for stalled encodes
   - Check if clip 3 has unusually long duration or complex content that triggers the stall

2. **MySQL IntegrityError on step_04_cut:** The foreign key constraint failure on `clip.pipeline_run_id` suggests a race condition or ordering issue. Ensure the pipeline_run record is committed to the database before clip records are inserted.

3. **Health check:** The celery service has `healthStatus: UNKNOWN` because there is no health check configured. Consider adding a Celery worker health check (e.g., `celery inspect ping`) to detect genuinely stuck workers.

4. **Monitoring:** Add CloudWatch alarms for:
   - Celery task failure rate
   - Extended idle periods (CPU below threshold for extended time)
   - Log pattern matching for "FFmpeg stalled" errors
