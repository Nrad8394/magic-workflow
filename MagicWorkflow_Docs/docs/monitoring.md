# Monitoring

The optional monitoring profile adds metrics, dashboards and centralised logs.

```bash
make up-full      # core + Prometheus + Grafana + Loki + Promtail + node-exporter
```

## Components

| Service | Role |
|---------|------|
| **Prometheus** | scrapes metrics (node, MinIO, Mattermost) |
| **Grafana** | dashboards at `https://grafana.<domain>` |
| **Loki** | log aggregation backend |
| **Promtail** | ships every container's logs to Loki (Docker SD) |
| **node-exporter** | host CPU/RAM/disk/network metrics |

Grafana comes pre-provisioned with **Prometheus** and **Loki** datasources. Drop
dashboard JSON into `config/grafana/dashboards/` to auto-load it.

## What's scraped

`config/prometheus/prometheus.yml` targets:

- `node-exporter:9100` — host metrics
- `minio:9000/minio/v2/metrics/cluster` — object storage
- `mattermost:8067` — Mattermost performance metrics
  (Enterprise; enable with `MM_METRICSSETTINGS_ENABLE=true`)

Add Nextcloud metrics via the `serverinfo` app + a community exporter, and
Postgres via `postgres_exporter` if you want DB dashboards.

## Logs

All container logs flow to Loki via Promtail. In Grafana → Explore → Loki, query
by container:

```
{container="magicworkflow-nextcloud-app-1"}
{container=~"magicworkflow-mattermost.*"} |= "error"
```

Container logs are also capped on disk (json-file, 10 MB × 3) so they can't fill
the host.

## Alerting

Wire Prometheus Alertmanager (or Grafana alerting) to **Mattermost** via an
incoming webhook so alerts land in an `#ops` channel — closing the loop within
the suite. See the Mattermost integration docs for webhook setup.
