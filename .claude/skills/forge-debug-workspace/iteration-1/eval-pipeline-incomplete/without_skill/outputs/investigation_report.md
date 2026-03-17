# Investigation Report: Pipeline Run 019cf473-e5f0-7666-834e-ab8a3b5a95ef

## Summary

The pipeline run was **killed by a Celery worker shutdown** caused by an ECS deployment rolling update, and was subsequently **deleted by the user** approximately 8 minutes later. The pipeline record no longer exists in the database.

## Timeline (all times UTC, March 16 2026)

| Time | Event |
|------|-------|
| 00:46 | GitHub Actions run "Bump celery to 4 vCPU/16GB and add FFMPEG_THREADS=1 env var" triggers Terraform apply on the services workspace. This changed celery from 2 vCPU/8GB to 4 vCPU/16GB. |
| 01:54 | ECS starts new celery task `c8193806` as part of the rolling deployment. |
| 02:22:42 | Pipeline `019cf473-e5f0-7666-834e-ab8a3b5a95ef` is submitted. The API sends task `step_01_download` to the Celery queue. Celery worker `c8193806` receives it. |
| 02:24:14 | ECS starts the replacement celery task `23057af6` (new deployment with 4 vCPU/16GB). |
| 02:27:56 | Worker `c8193806` syncs with the new worker `23057af6`. |
| 02:28:41 | ECS stops celery task `c8193806` ("Warm shutdown"). The download task for pipeline `019cf473` is killed mid-execution. The task never completes, never reports progress, and never produces artifacts. |
| 02:30:13 | User deletes the pipeline run via the API. The `DeleteRunController` removes the record (0 artifacts, 0 clips). |

## Root Cause

The pipeline was caught in the middle of an ECS rolling deployment. The commit `4f2eaa5` ("Bump celery to 4 vCPU/16GB and add FFMPEG_THREADS=1 env var") triggered a Terraform apply that updated the celery ECS service task definition. During the rolling update, ECS replaced the old container running the Celery worker.

The Celery worker `c8193806` had already received the `step_01_download` task but was terminated before it could finish downloading. The "Warm shutdown" signal tells Celery to stop accepting new tasks and finish current ones, but ECS has a default `stopTimeout` (typically 30 seconds to 2 minutes) after which it force-kills the container. The download step likely needed more time than the stop timeout allowed.

## Why the Pipeline Record Does Not Exist in the Database

The user manually deleted the pipeline run at 02:30:13 UTC (about 8 minutes after it was created). The `DeleteRunController` logs confirm: "Deleted pipeline run 019cf473-e5f0-7666-834e-ab8a3b5a95ef, removed 0 artifacts and 0 clips."

## Evidence

- **CloudWatch Logs** (`/ecs/forge-dev`):
  - `celery/celery/c8193806`: Task received at 02:22:42, warm shutdown at 02:28:42
  - `api/api/e1913159293343bea25bc74852a2eb05`: Task submitted at 02:22:42, pipeline deleted at 02:30:13
- **ECS Service Events** (`forge-dev-celery`):
  - Task `c8193806` stopped at 19:28:41 PDT (02:28:41 UTC)
  - Task `23057af6` started at 19:24:14 PDT (02:24:14 UTC)
- **GitHub Actions** run #23123291343: "Bump celery to 4 vCPU/16GB" applied at 00:46:50 UTC
- **Database**: Pipeline run `019cf473-e5f0-7666-834e-ab8a3b5a95ef` does not exist (was deleted)

## Pattern Observed

This is not an isolated incident. The same pattern ("Pipeline stale: no activity for 15 minutes. The worker may have crashed.") appears on two other recent pipeline runs:
- `019cf84c-4a45-7260-bd6b-16665049744d` (failed at export step, progress 85%)
- `019cf54e-3778-71ec-93f4-525a4af1dac7` (failed at export step, progress 85%)

These suggest the celery worker is crashing or being replaced during long-running pipeline steps.

## Recommendations

1. **Increase ECS stop timeout** for the celery service. The default is 30 seconds; for long-running video processing tasks, consider setting `stopTimeout` to 120-300 seconds in the ECS task definition to give Celery time to finish in-flight work.

2. **Implement Celery task retry/resume logic.** If the worker is killed, the task should be retried by another worker. Consider using Celery's `acks_late=True` setting so tasks are only acknowledged after completion, allowing them to be re-delivered if the worker dies.

3. **Consider a deployment strategy that drains tasks first.** Before deploying, the pipeline could be paused or the worker could be signaled to stop accepting new tasks, wait for in-flight tasks to complete, and then be replaced.

4. **Add deployment guards.** Check for active pipeline runs before applying Terraform changes to the celery service. The `StalePipelineService` already detects stale runs; a similar check could prevent deployments when pipelines are active.
