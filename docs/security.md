# Security Checklist

Hardening verification for the Stoat VPS. Run these checks after provisioning and periodically.

## Footguns Checklist

### SSH

- [ ] Password authentication disabled
- [ ] Root login disabled

```bash
# Verify SSH config
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
# Expected:
#   passwordauthentication no
#   permitrootlogin no
```

> NOTE: `bin/provision.sh --allow-password` leaves password + root logins enabled for people who explicitly want that trade-off. If you use that flag, set strong passwords and consider restricting SSH by IP or VPN.

### Firewall

- [ ] Vultr firewall denies all except 22/80/443
- [ ] UFW denies all except 22/80/443

```bash
# Verify UFW
sudo ufw status verbose
# Expected: Default deny (incoming), allow 22, 80, 443
```

### Fail2ban

- [ ] Fail2ban enabled for sshd

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
# Expected: sshd jail active with maxretry=5
```

### Docker

- [ ] Docker log rotation configured

```bash
cat /etc/docker/daemon.json
# Expected: max-size 10m, max-file 3
```

### Port Exposure

- [ ] No DB/cache/admin ports exposed to internet

```bash
# Check what's listening on all interfaces
sudo ss -lntp | grep -v '127.0.0.1\|::1'
# Only ports 22, 80, 443 should appear on 0.0.0.0 or *
```

```bash
# Verify Docker containers aren't publishing extra ports
docker compose -f /opt/stoat/upstream/compose.yml -f /opt/stoat/overrides/docker-compose.override.yml ps --format "{{.Name}} {{.Ports}}"
# Only caddy should show 0.0.0.0:80 and 0.0.0.0:443
```

### Backups

- [ ] Off-box backups working
- [ ] Restore tested at least once

```bash
# Run a test backup
cd /opt/stoat && bin/stoatctl backup --local-only
# Verify it appears in S3
aws s3 ls s3://YOUR-BUCKET/stoat-backup- --endpoint-url YOUR-ENDPOINT
```

### Updates

- [ ] Unattended security updates enabled
- [ ] Update procedure includes snapshot/rollback plan

```bash
sudo systemctl status unattended-upgrades
# Expected: active
```

## If Compromised

1. **Isolate**: Remove VPS from Vultr firewall group or shut it down
2. **Preserve**: Take a snapshot for forensics before making changes
3. **Assess**: Check auth logs (`/var/log/auth.log`), Docker logs, fail2ban logs
4. **Recover**: Restore from a known-good backup to a fresh VPS
5. **Rotate**: Change all credentials (SSH keys, app secrets, S3 keys)
6. **Review**: Check what data may have been accessed
