# Receipt result latency — 27 November 2026

The existing extraction is accurate, but fresh-photo results are not a millisecond operation. Production timings show that model inference dominates. The implementation from this investigation removes unnecessary worker startup dependencies; it does not claim to make AI extraction instantaneous.

## What was measured

- Read-only Cloud Logging queries explicitly scoped to project `receipt-nest`, service `processreceipt`, over the preceding eight days. No receipt was uploaded, retried, or sent to a model for this investigation.
- 52 paired processing/model timing entries, across two deployed revisions, from 22–27 November in Pacific time. These are instrumented runs, not every receipt in the project. All 52 worker outcomes were `completed`; that means the worker completed, not that every extracted field was final/validated.
- The current-revision baseline is 41 instrumented runs on `processreceipt-00126-hal`, deployed 25 November. The table below uses those 41 runs, with nearest-rank percentiles.
- Timing payloads contain durations and counts. Customer files, receipt contents, user IDs, and execution IDs are excluded from the checked-in report and benchmark data.

| Stage | p50 | p95 |
|---|---:|---:|
| Event delivery / startup | 754 ms | 3,298 ms |
| Receipt claim | 101 ms | 641 ms |
| Original-file preparation | 524 ms | 765 ms |
| AI extraction | 3,970 ms | 4,895 ms |
| Merchant normalization | 45 ms | 97 ms |
| Final validated commit | 117 ms | 165 ms |
| Worker total | 4,929 ms | 5,940 ms |
| Receipt creation to worker completion | 5,594 ms | 9,370 ms |

Phase percentiles are not additive. The final row is calculated per invocation before taking percentiles. It excludes photo selection, client compression, phone upload/preflight, and delivery of the final Firestore update to the phone. Mobile analytics already record transfer/acceptance timing, but no phone-upload latency distribution was available in the queried worker logs.

Across the full 52-run sample, AI extraction alone had a median around 3.9 seconds and a fastest observed call around 2.6 seconds. A six-instance, current-revision grouping showed a median 3.2 seconds of event delivery for each instance’s first observed request versus about 0.7 seconds for reused instances. This grouping is consistent with cold-start overhead but is not a controlled cold/warm experiment.

## Constraints kept

No model replacement, thinking-budget reduction, prompt shortening, output truncation, resized images, lossy recompression change, partial/unvalidated financial results, additional model calls, or cross-user extraction caches. No warm instances or scheduled keepalive calls. The mobile upload queue, plan checks, retry identities, and original documents remain unchanged.

The deployed receipt worker’s baseline is 1 CPU, 1 GiB, concurrency 80, maximum 10 instances, minimum zero, and a 300-second timeout in `us-central1`. The fix changes source dependency loading only.

## Plan and implementation

1. Locate avoidable work on the existing critical path.
2. Benchmark it in fresh Node 22 processes, without network/model requests.
3. Move version metadata out of the HTML/email dependency graph.
4. Compare exact extraction requests and results against the previous compiled worker, then run the entire backend suite.
5. Deploy only `processReceipt` and `processAdminReceiptRetry`, preserving runtime/scaling settings. Do not create artificial production receipts just to claim a new latency figure.

The import chain was:

`receipt-processor → receipt-processing-state → email-intelligence → email-content → cheerio + sanitize-html`

The receipt state module needed only `EMAIL_EXTRACTION_PIPELINE_VERSION`. A new lightweight `email-pipeline-version.ts` holds exactly the same `email-extraction-v6` string. Email intelligence re-exports it, and receipt state imports the lightweight module directly. Archived-email retry still loads the full email implementation when it is actually needed.

No receipt parser or validation code changed. Model ID, temperature, output limit, JSON mode, prompt text, original image/PDF bytes, HEIC conversion, category logic, merchant matching, ownership checks, retry/edit merging, and processing history are unchanged.

## Reproducible startup evidence

Fresh processes were alternated between baseline and optimized builds. Each variant had two warmup processes and 12 measured samples. Both builds used the same installed dependencies on this Mac, under Node 22.20.0. This is a module-startup benchmark, not production end-to-end latency.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Median module initialization | 132.4 ms | 82.8 ms |
| Median process CPU time | 168.1 ms | 98.9 ms |
| Median RSS | 93.0 MiB | 80.0 MiB |
| Loaded modules | 798 | 535 |
| Email parser modules | 18 | 0 |

That is **37.5% less module-initialization time**, about **50 ms** in this local benchmark, and 263 fewer loaded modules. An independent earlier run measured about 135 → 83 ms. Expect a modest cold-start improvement, not a multi-second improvement, and no direct model-inference speedup on already-warm instances. Production improvement is not yet quantified.

Raw numeric benchmark samples: [receipt-startup-benchmark-2026-11-27.json](receipt-startup-benchmark-2026-11-27.json).

Reproduce with the standalone offline script:

```sh
node scripts/benchmark_receipt_worker_startup.cjs /path/to/baseline/bootstrap.js /path/to/optimized/bootstrap.js
```

The baseline needs to be compiled from the pre-change source with the same dependencies. The temporary baseline used here is not an app or deployment artifact.

## Validation

- 17 offline contract checks passed, including comparisons with the previous compiled worker for original JPEG/PNG/WebP/PDF inputs, unchanged prompt/configuration, HEIC conversion, malformed/partial responses, service failures, and ownership/idempotency guards.
- The exact backend source compiled successfully. Full backend suite: **213 passed, zero failed, one existing opt-in browser integration skipped** (214 tests total).
- New regression coverage verifies both receipt-worker entry points do not load HTML/email parser modules during startup, and email extraction/history retain the same version metadata.
- The mobile runtime/UI was not changed by this performance fix. The prior mobile verification remains separate; backend tests do not replace a production before/after latency comparison.

## Other options assessed

| Option | Decision under the current constraints |
|---|---|
| Direct Cloud Storage model input | Previously benchmarked in this repo: slower on three of four synthetic pairs. Keep original inline transport. |
| Lower-resolution images, lower thinking budget, or another model | Potentially faster, but cannot promise unchanged accuracy; not shipped. |
| Stream partial JSON fields | Earlier output does not mean a validated total/date. Keep complete validated results. |
| Warm workers or provisioned throughput | Recurring spending conflicts with this request; not enabled. |
| Parallel batch transfers | Can reduce total batch time, but may slow the first upload on limited bandwidth and complicate free-plan enforcement. Needs phone-side timing evidence before changing the current queue. |
| Merchant caching / skipping final transactions | Current median merchant work is only tens of milliseconds. Stale aliases or weaker concurrent-edit protection would be a poor trade. |
| Prefetch SDK auth using private internals | Unsupported SDK API; not shipped. |
| Exact-duplicate extraction cache | Helps repeats, not first-time/new receipts, and adds invalidation/privacy/read-write concerns. Not introduced. |

The practical target is immediate feedback and the shortest measured path to a fully validated result. Indexed web search and fresh receipt extraction do different amounts of work; millisecond final extraction is not demonstrated by this architecture under unchanged quality and spending.

## Official references

- [Google latency optimization guidance](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/deploy/consumption-options): distinguishes first-token responsiveness from completion time and describes quality/cost tradeoffs.
- [Google image input documentation](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/capabilities/image-understanding): documents inline/Storage inputs. Support alone is not evidence that a transport will be faster for this app.
- Existing backend performance notes document the prior direct-Storage benchmark and why minimum instances remains zero.

## Deployment verification

The targeted deployment completed successfully on 27 November 2026 (Pacific). Both workers report `ACTIVE`. Their configurations were re-read after deployment: 1 CPU, 1 GiB, concurrency 80, maximum 10 instances, minimum zero, 300-second timeout, with entry points unchanged. Retry-worker settings also match its recorded pre-deploy configuration.

- `processReceipt`: `processreceipt-00127-zel`.
- `processAdminReceiptRetry`: `processadminreceiptretry-00022-nuk`.

No new customer/model invocation was generated for verification. These are deployment/configuration and offline-contract checks; no production end-to-end speedup is claimed without a comparable post-deploy sample. No mobile rebuild is needed for this backend-only runtime change.
