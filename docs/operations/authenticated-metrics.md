# Authenticated metrics

`GET /metrics` requires the existing kernel read admission. Give the scraper an
ordinary enrolled person/session credential with current Viewer authority over
the kernel surface. Missing or invalid credentials return 401; revoked or denied
read authority refuses the scrape. Store the bearer credential in a private file
mounted into Prometheus, and use the installation's HTTPS endpoint:

```yaml
scrape_configs:
  - job_name: oshal-kernel
    scheme: https
    metrics_path: /metrics
    authorization:
      type: Bearer
      credentials_file: /run/secrets/oshal-metrics-token
    static_configs:
      - targets: ["oshal.example.internal:443"]
```

Replace the target with the actual TLS ingress, and configure its trusted CA when
needed. The file contains only the credential value; it is not an admin token
requirement. Prometheus documents this header configuration in its
[scrape configuration reference](https://prometheus.io/docs/prometheus/latest/configuration/configuration/).

`oshal_http_requests_total` counts completed router responses, including admission
refusals and unmatched paths. `oshal_http_request_duration_seconds` measures time
until the handler returns its response, with fixed 5 ms–10 s buckets plus infinity;
it excludes later streaming/body delivery. Labels are the router's `MatchedPath`
template, ten fixed method values (unknown methods become `OTHER`) and six status
classes. Unmatched requests use `__unmatched__`. The shared router collector holds
at most 256 normal label combinations and 60 overflow combinations; additional
combinations accumulate under `__overflow__`. Templates over 256 bytes also use
overflow. It never labels requests by URI/query, caller, tenant, token or content.
An in-progress scrape appears in the next scrape once its response has completed.
HTTP observations are distinct from the existing kernel admission/span counters.

On Linux, `oshal_process_resident_memory_bytes`, `oshal_process_threads` and
`oshal_process_cpu_seconds` are gauges read from bounded `/proc/self` files. CPU
seconds are cumulative user plus system process time using the observed ELF
`AT_CLKTCK` frequency; they exclude child processes and are not a CPU percentage.
RSS uses Linux's current `VmRSS` observation, whose accounting can be approximate.
Each unavailable field is omitted; other operating systems omit these process
gauges. There are no invented zero values, host CPU, network or disk observations.
The source contracts are documented by the Linux
[process filesystem](https://docs.kernel.org/filesystems/proc.html) and
[ELF auxiliary vector](https://man7.org/linux/man-pages/man3/getauxval.3.html).

Counters and histograms start fresh when this router/process is constructed.
These source changes do not install Prometheus or certify a live ingress scrape.
