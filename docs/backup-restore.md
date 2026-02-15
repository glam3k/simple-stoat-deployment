# Backup & Restore

## What Gets Backed Up

| Component | Source | Why |
|-----------|--------|-----|
| MongoDB | `docker exec mongodump` | User accounts, messages, channels, servers |
| MinIO | `data/minio/` directory | Uploaded files, avatars, emojis, attachments |
| Config | `Revolt.toml`, `.env.web`, `Caddyfile` | VAPID keys, encryption key, domain config |

## Setup

1. Copy the backup env template and fill in your S3 credentials:

```bash
cp /opt/stoat/overrides/env/backup.env.template /opt/stoat/backup.env
nano /opt/stoat/backup.env
```

2. Install the AWS CLI (preferred) or rclone. Stoat will read `BACKUP_S3_*`
   values from `backup.env` and export them for the CLI automatically. If you
   use rclone, configure a remote (defaults to `stoat-backup`, override with
   `BACKUP_RCLONE_REMOTE`).

```bash
sudo apt-get install -y awscli
# optional: sudo apt-get install -y rclone && rclone config
```

## Manual Backup

```bash
cd /opt/stoat
bin/stoatctl backup
# or skip S3 upload:
bin/stoatctl backup --local-only
```

## Automated Backups (Cron)

Add a daily cron job:

```bash
crontab -e
```

Add this line (runs at 3 AM daily):

```
0 3 * * * cd /opt/stoat && bin/stoatctl backup >> /var/log/stoat-backup.log 2>&1
```

## Retention

Retention is controlled via `BACKUP_RETAIN_DAILY` in `backup.env` (default 7 most recent backups). Additional weekly/monthly knobs are placeholders for future rotation schemes.

## Restore to Same Server

```bash
# Restore most recent backup from S3
cd /opt/stoat
bin/stoatctl restore latest

# Restore a specific backup
bin/stoatctl restore stoat-backup-20260101-030000

# Restore from a local archive file
bin/stoatctl restore --from-file /path/to/stoat-backup-20260101-030000.tar.gz
```

## Restore to Fresh Server

1. Provision the new VPS: `sudo bin/provision.sh`
2. Deploy Stoat: `bin/stoatctl deploy core`
3. Stop services: `bin/stoatctl stop core`
4. Set up backup.env with your S3 credentials
5. Restore: `bin/stoatctl restore latest`
6. Update DNS to point to the new VPS IP

## Restore from Local File

If you have a backup archive file (e.g., transferred via scp):

```bash
bin/stoatctl restore --from-file /path/to/stoat-backup-20260101-030000.tar.gz
```

## Testing Restores

Test your restore process regularly. The easiest way:

1. Spin up a throwaway VPS on Vultr
2. Run provision.sh + `bin/stoatctl deploy core`
3. Run `bin/stoatctl restore latest`
4. Verify the instance works
5. Destroy the throwaway VPS
