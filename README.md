# Backup via Restic
- Documentation in Code & in Obsidian
- Passwords in Bitwarden
  - `[restic] env file & backup passwords`
  - Passwords have to be placed in file in format `restic-pw-$service`

## Run restic outside of script
```
cd /opt/restic
source restic-env.sh $service
restic snapshots
```

## Article on restic
<https://medium.com/codex/restic-backup-i-simple-and-beautiful-backups-bdbbc178669d>

# infra-restic
