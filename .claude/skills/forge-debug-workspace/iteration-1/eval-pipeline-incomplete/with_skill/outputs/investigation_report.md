# Investigation Report: Pipeline Run 019cf473-e5f0-7666-834e-ab8a3b5a95ef

## Summary

The pipeline failed at **step 4 (cut)** due to a **missing database record**. The `pipeline_run` row for this ID does not exist in the `forge` database, which caused a foreign key constraint violation when the celery worker attempted to insert clip records during the cut step.

## Timeline (all times UTC, 2026-03-16)

| Time | Event |
|------|-------|
| 04:23:24 | Celery receives `step_01_download` task for this run ID |
| 04:23:24 | WARNING: "PipelineRun not found: 019cf473-e5f0-7666-834e-ab8a3b5a95ef" |
| 04:23:24 | WARNING: "Clip not found: run=019cf473-e5f0-7666-834e-ab8a3b5a95ef, index=0" |
| 04:23:24 | Download proceeds despite missing DB record |
| 04:23:33 | Download complete (Jeff Bezos In 1999 On Amazon's Plans Before The Dotcom Crash, 464s, 37.6MB) |
| 04:23:33 | WARNING: "PipelineRun not found for update: 019cf473-e5f0-7666-834e-ab8a3b5a95ef" |
| 04:23:33 | Audio extraction and upload to S3 (step 1 complete) |
| ~04:24:40 | Step 2 (transcribe) completes, step 3 (analyze) starts |
| 04:24:55 | OpenAI analysis response received (5 clips identified, $0.0081 cost) |
| 04:24:55 | WARNING: "PipelineRun not found for update" (repeated) |
| 04:24:55 | Step 3 complete, chains to step 4 (cut) |
| 04:24:57 | Step 4 downloads source video and analysis from S3 |
| 04:24:59 | **ERROR**: Step 04 failed with `IntegrityError(1452)` -- foreign key constraint on `clip.pipeline_run_id` referencing `pipeline_run.id` |

## Root Cause

The `pipeline_run` record with ID `019cf473-e5f0-7666-834e-ab8a3b5a95ef` was never created in the database (or was deleted before the celery task was dispatched). The celery worker logged multiple warnings about the missing record during steps 1-3 but continued processing because the download, transcribe, and analyze steps do not require writing to the `clip` table. Step 4 (cut) failed because it tries to INSERT rows into the `clip` table, which has a foreign key constraint (`clip_pipeline_run_id_foreign`) requiring a valid `pipeline_run.id`.

The pipeline run ID appears to be a valid UUIDv7 (time-based), and the prefix `019cf4` places it chronologically between the runs `019cf012` (2026-03-15 05:58 UTC) and `019cf54e` (2026-03-16 06:21 UTC), which is consistent with the actual execution time. This suggests the run was likely created via the API but the database transaction that creates the `pipeline_run` row either rolled back, was never committed, or the record was deleted before the celery task picked it up.

No API or worker (NestJS BullMQ) logs were found referencing this run ID, which may indicate the pipeline was triggered directly via the Celery broker (Redis) rather than through the normal API flow, or that the API/worker logs from that time have been rotated out.

## S3 Artifacts Produced

The following artifacts were successfully uploaded to S3 before the failure:

| Folder | Contents |
|--------|----------|
| `1-sources/` | `source.mp4` (39.4MB), `audio.wav` (14.9MB) |
| `2-transcripts/` | Transcription output |
| `3-analysis/` | `analysis.json` (133KB) -- 5 clips identified |
| `4-segments/` | 5 segments with transcripts (`segment_0` through `segment_4`) |

Missing folders (never created due to failure): `5-cropped/`, `5-cropped-effects/`, `5-cropped-subtitles/`, `6-final/`

## Database State

- No `pipeline_run` record exists for ID `019cf473-e5f0-7666-834e-ab8a3b5a95ef`
- No `clip` records exist (the INSERT that would have created them is what failed)
- The YouTube URL for this run was `https://www.youtube.com/watch?v=GltlJO56S1g` (same video used in multiple other runs)

## ECS Service State

The celery service (`forge-dev-celery`) was running normally during this period. The ECS task `6656695f18a64bb4b2590ecfc0922b5f` was active. Multiple deployments occurred on March 15 (19:24, 19:38, 23:11 PT), but none overlapped with the pipeline execution at 04:23 UTC (21:23 PT March 15).

## Recommendations

1. **Re-run the pipeline** through the normal API flow to ensure a `pipeline_run` record is created before the celery task is dispatched.
2. **Add a guard in the celery worker** to fail fast at step 1 if the `pipeline_run` record is not found, rather than proceeding through multiple steps only to fail at step 4. The current behavior wastes compute (download, transcription, OpenAI API call) on a run that cannot complete.
3. **Investigate how this task was dispatched** without a corresponding database record. Check if there is a race condition between the API creating the DB record and publishing the Celery task to Redis, or if someone triggered the task manually.
