# Celery Worker Health Investigation Report

**Date:** 2026-03-16
**Service:** forge-dev-celery
**Region:** us-east-1

## Executive Summary

The celery worker ECS service is **running and stable**, but the most recent pipeline run failed due to an FFmpeg stall during the subtitles step (step 10) for clip 3. The worker itself is not stuck or crashed; it is idle and awaiting new tasks. The perceived "slowness" is likely due to repeated pipeline failures rather than a service-level issue.

## Service Health

| Check | Result |
|-------|--------|
| ECS Service Status | ACTIVE, deployment COMPLETED |
| Running Tasks | 1/1 (desired = running) |
| Task Status | RUNNING since 2026-03-15 23:15 UTC |
| Container Health | UNKNOWN (no health check configured) |
| Task Resources | 4 vCPU, 16 GB RAM |
| Recent Restarts | 1 redeployment on 2026-03-15 (task replaced, new task started successfully) |
| Failed Tasks in Deployment | 0 |

The service has been at steady state since 2026-03-16 11:18 AM. No OOM kills, no crash loops, no health check failures.

## Recent Pipeline Runs (Database)

All 10 most recent pipeline runs have **failed**. All target the same YouTube video (`GltlJO56S1g`):

| Run ID | Status | Failed At Step | Progress | Created |
|--------|--------|---------------|----------|---------|
| 019cf84c... | FAILED | export | 85% | 2026-03-16 20:17 |
| 019cf54e... | FAILED | export | 85% | 2026-03-16 06:21 |
| 019cf029... | FAILED | download | 10% | 2026-03-15 06:22 |
| 019cf012... | FAILED | download | 10% | 2026-03-15 05:58 |
| 019cf008... (x2) | FAILED | download | 10% | 2026-03-15 05:46 |
| 019ceffe... | FAILED | download | 10% | 2026-03-15 05:36 |
| 019cefb7... (x3) | FAILED | download | 10% | 2026-03-15 04:14-04:18 |

**Pattern:** Earlier runs failed at the download step. The two most recent runs made it much further (85% progress) but failed at the export stage.

## Most Recent Run Analysis (019cf84c...)

### Clip Status

| Clip | Status | Title | Duration |
|------|--------|-------|----------|
| 0 | COMPLETED | Why Warehouses Beat Retail Stores (Cost Math) | 34s |
| 1 | COMPLETED | Entering Industries You 'Don't Know' (The Real Playbook) | 41s |
| 2 | COMPLETED | Growth Is an Execution-Risk Game | 59s |
| 3 | FAILED | It's Easy to Predict Winners Exist, Hard to Pick Them | 97s |

3 of 4 clips completed successfully. Only clip 3 failed.

### S3 Artifacts

All step folders exist (1-sources through 7-publish). Clips 0, 1, and 2 have complete final exports and publish artifacts. Clip 3 is missing from 6-final and 7-publish.

### Root Cause: FFmpeg Stall on Clip 3

The error logs show a clear sequence:

1. **S3 NoSuchKey warnings** for `segment_X_silence_filter.json` files (clips 0-3) -- these appear to be non-fatal (clips 0-2 completed despite this).
2. **FFmpeg stall on clip 3** at step 10 (subtitles): The horizontal version (`final_horizontal_3.mp4`, 50 MB) completed in 150 seconds, but the vertical version (`final_vertical_3.mp4`) stalled with no output for 120 seconds, triggering the stall timeout.
3. The task raised `FFmpegError: FFmpeg stalled (no output for 120s) encoding final_vertical_3.mp4`.

Clip 3 is the longest clip at 97 seconds; the other clips are 34-59 seconds. The longer duration likely contributed to the FFmpeg encoding stall for the vertical version, which involves more complex filter chains (cropping + subtitle burn-in).

## Errors Found in Last 6 Hours

1. **S3 NoSuchKey** -- `segment_X_silence_filter.json` missing for all 4 clips (non-fatal, clips still completed)
2. **FFmpeg stall** -- `final_vertical_3.mp4` stalled after 417s, killed; then raised FFmpegError at stall timeout of 120s
3. **Task failure** -- `step_10_subtitles` task marked as FAILURE

## Conclusions

1. **The celery worker is healthy.** The ECS service is running normally with no crashes, restarts, or OOM kills.
2. **The pipeline failure is an application-level issue**, not an infrastructure problem. Specifically, FFmpeg stalls when encoding vertical video with subtitles for longer clips.
3. **3 of 4 clips completed successfully** in the most recent run. Only the longest clip (97s) triggered the FFmpeg stall.
4. **The `silence_filter.json` S3 errors** are present for all clips but don't block processing. This may be a missing feature or a step that was skipped. Worth investigating separately.

## Recommendations

1. **Increase the FFmpeg stall timeout** for longer clips, or make it proportional to clip duration. The current 120s timeout may be too aggressive for clips approaching 2 minutes.
2. **Investigate the silence_filter.json S3 errors.** These files are expected but missing, suggesting the silence detection step may not be producing output. This is non-blocking but may affect output quality.
3. **Consider adding a container health check** to the celery task definition. Currently healthStatus is UNKNOWN, making it harder to detect a truly stuck worker.
4. **Retry clip 3 individually** if the pipeline supports per-clip retries, or re-run the full pipeline.
