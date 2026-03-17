# Investigation Report: Recent Pipeline Failures

**Date:** 2026-03-16
**Scope:** Last 3 days of pipeline runs and CI/CD activity

## Summary

All 10 pipeline runs in the last 2 days have failed. There are zero successful completions. The failures fall into three distinct categories:

1. **YouTube bot-detection blocking downloads** (6 runs, Mar 15)
2. **yt-dlp format selection error** (2 runs, Mar 15)
3. **Export-stage stale pipeline timeout** (2 runs, Mar 16)

Additionally, there was one GitHub Actions CI failure on March 7 (AWS credential misconfiguration), but it was resolved in the subsequent run.

---

## ECS Service Health

All four services are healthy and running at desired count:

| Service | Status | Running/Desired |
|---------|--------|-----------------|
| forge-dev-api | ACTIVE, steady state | 1/1 |
| forge-dev-worker | ACTIVE, steady state | 1/1 |
| forge-dev-celery | ACTIVE, steady state | 1/1 |
| forge-dev-frontend | ACTIVE, steady state | 1/1 |

No restarts, OOM kills, or deployment issues detected. Services are stable.

---

## Pipeline Failure Details

### Issue 1: YouTube Bot Detection (6 runs, highest impact)

**Runs affected:** 019cefb4, 019cefb5, 019cefb7, 019ceffe, 019cf008-33, 019cf008-6b
**Time window:** Mar 15 04:14 - 05:46 UTC
**Step:** download (step 1)
**Video:** GltlJO56S1g

**Error:**
```
Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for the authentication.
```

**Root cause:** YouTube is rate-limiting or bot-flagging the yt-dlp requests from the ECS task's IP. This is a known yt-dlp issue where YouTube requires cookie-based authentication for certain IPs (especially cloud/datacenter IPs).

**Recommended fix:**
- Configure yt-dlp with cookies. Either inject browser cookies via Secrets Manager or use an OAuth2 token.
- Consider using a proxy/residential IP rotation service for downloads.
- Update yt-dlp to the latest version, as newer versions sometimes have workarounds.

### Issue 2: yt-dlp Format Not Available (2 runs)

**Runs affected:** 019cf012, 019cf029
**Time window:** Mar 15 05:58 - 06:22 UTC
**Step:** download (step 1)
**Video:** GltlJO56S1g (same video)

**Error:**
```
Requested format is not available. Use --list-formats for a list of available formats
```

**Root cause:** After the bot-detection was presumably resolved (or bypassed), the format selection string in yt-dlp is requesting a format combination that is not available for this video. This could mean the video has restricted formats, or the hardcoded format string (e.g., `bestvideo+bestaudio/best`) is too specific.

**Recommended fix:**
- Review the yt-dlp format selection string in the content-forge download step.
- Use a more flexible fallback format like `bestvideo*+bestaudio/best`.

### Issue 3: Export-Stage Stale Timeout (2 runs, most recent)

**Runs affected:** 019cf54e (Mar 16 06:21), 019cf84c (Mar 16 20:17)
**Step:** export (step 11), sub-step "Trimming for publish"
**Progress:** 85%

**Error:**
```
Pipeline stale: no activity for 15 minutes. The worker may have crashed.
```

**What S3 shows:** Both runs actually produced substantial output. For run 019cf84c:
- Folders 1-sources through 7-publish all exist
- Clips 0, 1, 2 were fully exported and published (6-final + 7-publish artifacts present)
- Clip 3 is marked as failed in the database

**Clip status for run 019cf84c:**
- Clip 0: completed
- Clip 1: completed
- Clip 2: completed
- Clip 3: **failed** (longest clip, 31.3s - 128.5s, ~97 seconds of source video)

**Clip status for run 019cf54e:**
- Clip 0: **failed** (same time range 31.3s - 128.5s)
- Clip 1: completed
- Clip 2: completed
- Clip 3: **failed** (longest clip, 298.8s - 426.6s, ~128 seconds)
- Clip 4: completed

**Root cause:** The longer clips (97s and 128s of source video) are consistently failing during the export/publish trimming phase. The celery worker appears to stop sending progress updates, triggering the 15-minute stale timeout. This is likely either:
- An FFmpeg process hanging or crashing on longer clips (possibly memory-related, since the celery task has 4 vCPU / 16 GB with FFMPEG_THREADS=1)
- A silent worker crash that doesn't produce an error log (no ERROR entries found in CloudWatch for the last 3 days)

The fact that shorter clips complete fine but longer ones fail consistently suggests a resource or timeout constraint.

**Recommended fix:**
- Check if the celery hard time limit is being hit for longer clips.
- Inspect whether FFmpeg is segfaulting on these longer segments (check dmesg or add FFmpeg stderr logging).
- Consider increasing the stale timeout or adding a heartbeat mechanism during long FFmpeg operations.
- The 7-publish folder has partial results; the pipeline could potentially be resumed from export for just the failed clips.

---

## GitHub Actions CI/CD

| Date | Run ID | Status | Details |
|------|--------|--------|---------|
| Mar 7 09:19 | 22796343073 | **Failed** | AWS credential loading error in shared job |
| Mar 7 09:20 | 22796361895 | Success | Fixed on retry |
| Mar 11-15 | Multiple | Cancelled (3x) | Likely superseded by newer commits |
| Mar 15-16 | Multiple | Success (5x) | All recent Terraform runs passing |

The CI failure on Mar 7 was a transient AWS credentials issue ("Could not load credentials from any providers") and was resolved in the immediately following run. No action needed.

---

## Key Findings

1. **No pipeline run has completed successfully in the last 2 days.** Every single run (10 total) ended in failure.
2. **Two distinct problems exist:**
   - yt-dlp is being blocked by YouTube bot detection from the ECS task's IP (Mar 15, now partially resolved since later runs got past download).
   - Long clips are causing the celery worker to go stale during the export/publish phase, likely due to FFmpeg hanging (Mar 16, ongoing).
3. **CloudWatch shows zero ERROR log entries** for celery, worker, and api services over the past 3 days. This is suspicious and suggests either: the worker is crashing without logging, or log delivery is delayed/broken.
4. **Infrastructure is healthy.** All ECS services are running, steady state, no restarts. The Terraform CI pipeline is green.

## Recommended Next Steps

1. **Immediate:** Update yt-dlp in the content-forge Docker image to the latest version and configure cookie-based YouTube authentication.
2. **Immediate:** Investigate why the celery worker produces no CloudWatch ERROR logs despite pipeline failures. Check if the log level is misconfigured or if errors are being swallowed.
3. **High priority:** Debug the export-stage failure for long clips. SSH/ECS exec into the celery container during a run to monitor FFmpeg processes and memory usage.
4. **Medium priority:** Consider adding a retry mechanism for the export step on individual clips, so that 3 successful clips out of 4 are not lost when one fails.
