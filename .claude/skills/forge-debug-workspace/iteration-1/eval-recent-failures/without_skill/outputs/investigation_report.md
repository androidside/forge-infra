# Pipeline Failures Investigation Report

**Date:** 2026-03-16
**Repository:** forge-infra (androidside/forge-infra)
**Workflow:** Terraform (`.github/workflows/terraform.yml`)

## Summary

Out of 10 recent pipeline runs, 4 were non-successful: 1 failure and 3 cancellations. The most recent runs (Mar 15-16) are now succeeding after manual workflow_dispatch runs were used to recover.

## Non-Successful Runs

### 1. FAILURE - Mar 7 (Run #22796343073)

- **Commit:** `96f00ac` - "Initial infrastructure: Terraform modules, environments, scripts, CI/CD"
- **Failed Step:** "Configure AWS Credentials" in the `shared` job
- **Root Cause:** The AWS OIDC role-to-assume (`secrets.AWS_DEPLOY_ROLE_ARN`) was not yet configured or was incorrect at the time of the initial infrastructure commit. This was the very first pipeline run for the repo.
- **Impact:** No Terraform plan or apply executed. The `services` job was skipped as a downstream dependency.
- **Resolution:** Likely resolved by configuring the `AWS_DEPLOY_ROLE_ARN` secret in GitHub repo settings before subsequent runs.

### 2. CANCELLED - Mar 11 (Run #22941190552)

- **Commit:** `41905ff` - "Add Google AI secret, celery env vars, DB access, and production fixes"
- **Cancelled Step:** "Terraform Plan" in the `shared` job
- **Duration before cancellation:** ~6 hours (started 07:14 UTC, cancelled ~13:19 UTC)
- **Root Cause:** Terraform Plan hung/stalled, likely due to a DynamoDB state lock contention or an AWS API call that never returned. The plan step started at 07:14:30 and never completed.
- **Impact:** No infrastructure changes were applied for this commit via CI. The `services` job was skipped.

### 3. CANCELLED - Mar 15, 05:20 UTC (Run #23104047541)

- **Commit:** `29cd6ba` - "Add YouTube cookies secret, ECS Exec, and debug script"
- **Cancelled Step:** "Terraform Plan" in the `shared` job
- **Duration before cancellation:** ~6 hours (started 05:20 UTC, cancelled ~11:25 UTC)
- **Root Cause:** Same pattern as #2 - Terraform Plan hung for ~6 hours. This is consistent with a stale state lock from the previous cancelled run, or a similar AWS API timeout. The commit `0f93851` ("Add Terraform state lock auto-recovery and concurrency guard") was added afterward to address this exact issue.
- **Impact:** No infrastructure changes applied via CI.

### 4. CANCELLED - Mar 15, 20:36 UTC (Run #23118799937)

- **Commit:** `cae7a4f` - "Bump celery to 2 vCPU/8GB and add ephemeral storage support"
- **Cancelled Step:** "Terraform Plan" in the `shared` job
- **Duration before cancellation:** ~6 hours (started 20:48 UTC, cancelled ~02:48 UTC next day)
- **Root Cause:** Same Terraform Plan hang pattern. Even though the lock auto-recovery feature had been added in `0f93851`, this run still stalled. The GitHub Actions 6-hour job timeout appears to be what eventually cancelled these runs.
- **Impact:** No infrastructure changes applied via CI. Slack notification was sent (successfully).

## Recovery Actions Already Taken

After the cancellations, two **manual workflow_dispatch runs** were triggered on Mar 15 at 22:43 UTC:

1. **Run #23121044624** - Manual `shared` workspace apply - **SUCCESS**
2. **Run #23121045917** - Manual `services` workspace apply - **SUCCESS**

These successfully applied the pending infrastructure changes.

## Subsequent Successful Runs

- **Run #23123291343** (Mar 16 00:46) - Push, no shared/services changes detected, skipped. SUCCESS.
- **Run #23125884560** (Mar 16 02:52) - Push, no shared/services changes detected, skipped. SUCCESS.

## Current Infrastructure Status

All 4 ECS services are healthy and at steady state:

| Service | Status | Running | Desired |
|---------|--------|---------|---------|
| forge-dev-api | ACTIVE | 1 | 1 |
| forge-dev-worker | ACTIVE | 1 | 1 |
| forge-dev-celery | ACTIVE | 1 | 1 |
| forge-dev-frontend | ACTIVE | 1 | 1 |

No stale Terraform state locks are currently present in DynamoDB (only normal md5 digest entries).

## Root Cause Analysis

The recurring issue is **Terraform Plan hanging for ~6 hours** in the `shared` workspace. Possible causes:

1. **DynamoDB state lock contention** - A cancelled run may leave a stale lock in DynamoDB. Subsequent runs attempt to acquire the lock and wait indefinitely. The auto-recovery logic added in commit `0f93851` tries to detect and force-unlock stale locks, but only on the retry path (after the first plan fails), and the first plan itself hangs waiting for the lock rather than failing fast.

2. **AWS API timeouts** - Large Terraform plans touching many AWS resources (VPC, RDS, ElastiCache, ALB, etc.) could hang if an AWS API call stalls.

3. **GitHub Actions 6-hour timeout** - The runs are being cancelled at approximately the 6-hour mark, which is the default GitHub Actions job timeout. There is no explicit `timeout-minutes` set on these jobs.

## Recommendations

1. **Add explicit job timeout** - Set `timeout-minutes: 30` (or similar) on the `shared` and `services` jobs to fail fast rather than waiting 6 hours.

2. **Add `-lock-timeout` to Terraform commands** - Use `terraform plan -lock-timeout=5m` so that lock waits fail after a reasonable period rather than hanging indefinitely.

3. **Improve the lock recovery logic** - The current auto-recovery in the workflow only triggers after the plan step fails. If the plan step hangs waiting for a lock, it never fails, so the recovery never runs. Consider adding a pre-plan step that checks for and clears stale locks.

4. **Set `cancel-in-progress: true`** in the concurrency group - Currently set to `false`. When rapid pushes happen, old runs should be cancelled to avoid lock contention from concurrent Terraform operations.
