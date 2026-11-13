# CCDC Practice Scripts (Rocky Linux)

| Script | Changes things? | What it does |
|---|---|---|
| `config.sh` | - | Settings for this box. **Edit first.** |
| `recon.sh` | No | Snapshot: IPs, ports, users, services, connections |
| `backup.sh` | No (writes backups only) | Backs up /etc, web root, homes, cron, DBs, binary hashes |
| `hunt.sh` | No | Looks for backdoors/persistence, flags findings |
| `harden.sh` | **Yes** | Firewall, SSH, SELinux, disable services, auditd, sysctl |
| `passwords.sh` | **Yes** | Walks through every login account: change / lock / skip |
| `score.sh` | No | Fake scoring engine. Run from a *different* VM |

Output goes to `/root/.ccdc/` (logs + backups).

## Get them on the box

```bash
sudo dnf install -y git
git clone <your-repo-url> ccdc && cd ccdc
chmod +x *.sh
```

## Practice run order

```bash
# On another VM:
./score.sh <target-ip>

# On the Rocky box:
vi config.sh                 # set scored services for this box
sudo ./recon.sh              # 1. what's here
sudo ./backup.sh             # 2. backup before touching anything
sudo ./passwords.sh          # 3. change passwords
sudo ./harden.sh --dry-run   # 4a. preview
sudo ./harden.sh             # 4b. apply (asks per section)
sudo ./hunt.sh               # 5. look for backdoors
```

Then watch `score.sh`: everything should still be UP.

## Practice loop on Proxmox

1. Snapshot the VM (`baseline`).
2. Teammate plants backdoors, then snapshot again (`dirty1`).
3. Run the scripts, time yourselves, and note what `hunt.sh` missed.
4. Roll back to `dirty1`, improve the scripts, commit, and repeat.

## Safety notes

- `harden.sh` refuses to disable root SSH if no one is in `wheel`. Still, **keep your SSH session open** and test a new login before closing it.
- `hunt.sh` never deletes anything. You decide what to remove.
- Read the competition rules before running anything against the real environment.
