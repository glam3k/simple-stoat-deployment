# Observability Add-on

This stack runs Loki, Promtail, Prometheus, Grafana, node-exporter, and cAdvisor
on the Stoat VPS so you can inspect logs and metrics without external services.

## Components

- **Loki** stores container logs on disk for a short retention window.
- **Promtail** tails `/var/lib/docker/containers/*/*-json.log` and ships entries to Loki.
- **Prometheus** scrapes node-exporter (host metrics), cAdvisor (per-container metrics),
  and Loki itself.
- **Grafana** connects to Prometheus and Loki so you can visualize everything via
  `https://GRAFANA_HOST`.

## Configuration

Every setting is driven from `/opt/stoat/.env`:

| Variable | Description |
|----------|-------------|
| `OBSERVABILITY_ENABLED` | Set to `0` to disable the add-on entirely |
| `GRAFANA_SUBDOMAIN` / `GRAFANA_FQDN` | Hostname where Grafana is served |
| `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` | Initial Grafana credentials |
| `PROMTAIL_STATE_DIR` | Persistent directory for Promtail `positions.yaml` |
| `OBS_LOKI_DATA_DIR`, `OBS_PROM_DATA_DIR`, `OBS_GRAFANA_DATA_DIR` | Data directories |
| `LOKI_RETENTION_DAYS`, `PROMETHEUS_RETENTION` | Storage retention horizons |
| `OBS_*_CPUS`, `OBS_*_MEMORY`, `OBS_*_MEMORY_RESERVATION` | Resource limits per component |

Adjust the values in `.env` before running `bin/stoatctl deploy observability` so the
stack fits your VPS size.

## Deploy / Access

```bash
bin/stoatctl deploy observability
# Grafana becomes available at https://grafana.example.com (or your override)
```

Promtail resumes from `positions.yaml` after restarts, but keep Docker's log rotation
thresholds reasonable (e.g., 50MB × 3 files) so it has time to catch up if Loki is
briefly unavailable.
