
#!/usr/bin/env bash
set -euo pipefail

# Create a file to verify the next rsync backup.
# Run as root on the production server.

FILE="/root/backup-test.txt"

{
    echo "Hostname: $(hostname)"
    echo "Created: $(date -Is)"
} > "$FILE"

chmod 600 "$FILE"

echo "=== BACKUP TEST FILE ==="
cat "$FILE"
echo
echo "Check this file on the backup server after the next backup."


