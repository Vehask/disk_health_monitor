# Proxmox Disk Health and Temperature Monitoring

Scripts for use in Proxmox Node to monitor S.M.A.R.T. health and temperature for HDDs/SSDs with e-mail alerts

Scripts are run as a cron job and will append to logfiles located in `/var/log/diskhealth/`

Disk health monitor appends to `dhmon.log`

Temp monitor appends to `dtemp.log` and `dtemp_stats.log`. Command `less -R +G /path/to/logfile.log` allows for color-coded output (-R) and displays from the bottom of the logfile (+G):

• **Green:** Default below 35 degrees celsius
• **Yellow:** Default between 35-45 degrees celsius  
• **Red:** above set YELLOW_TEMP_MAX value
• **Blue:** Start/completion messages ("=== Temperature Monitor Started/Completed ===")
  - `dtemp.log` contains entries for readings done at set intervals (intervals are set in /etc/crontab) and overwrites daily
  - `dtemp_stats.log` contains entries for daily Min/Max/Avg, as well as warnings for readings above 55 degrees. New log entries are made at midnight and entries older than 7 days are deleted

## Features

### Health Monitor (`dhmon.sh`)
- **S.M.A.R.T. Health Monitoring:** Checks all disks for SMART health status
- **Monthly Log Rotation:** Automatically clears logs on the 1st of each month
- **Email Alerts:** Sends notifications when disk health issues are detected
- **Configurable Exclusions:** Skip specific devices (e.g., USB drives)
- **Dependency Validation:** Checks for required tools before execution

### Temperature Monitor (`dtemp_monitor.sh`)
- **Real-time Temperature Monitoring:** Tracks disk temperatures at set intervals in /etc/crontab
- **Color-coded Output:** Visual temperature indicators in log files
- **Smart Alerting:** Email alerts only after temperatures exceed threshold for 30+ minutes
- **Daily Statistics:** Min/Max/Average temperature tracking with weekly retention
- **Dual Log System:** Separate logs for real-time data and long-term statistics
- **Test Email Function:** Built-in email testing to verify alert functionality

## Installation

### Prerequisites
```bash
# Install required dependencies
apt-get update
apt-get install smartmontools mailutils util-linux
```

### Setup
1. **Clone or download the scripts:**
```bash
mkdir -p /usr/local/bin/disk-monitoring
cd /usr/local/bin/disk-monitoring
# Place dhmon.sh and dtemp_monitor.sh here
```

2. **Make scripts executable:**
```bash
chmod +x dhmon.sh
chmod +x dtemp_monitor.sh
```

3. **Create log directories:**
```bash
mkdir -p /var/log/diskhealth
```

## Configuration

### Health Monitor Configuration
Edit `dhmon.sh` and update these variables:
```bash
EMAIL_RECIPIENT="admin@yourdomain.com"  # Change to your own e-mail
SEND_EMAIL=true                         # Send alert when warnings are detected
EXCLUDED_DISKS=("/path/device")         # Add devices to exclude (Example:"/dev/sdo")
```

### Temperature Monitor Configuration
Edit `dtemp_monitor.sh` and customize these settings:
```bash
EMAIL_RECIPIENT="admin@yourdomain.com"  # Change to your own e-mail
SEND_EMAIL=true                         # Send alert when temperatures higher than TEMP_THRESHOLD are detected for more than ALERT_DURATION minutes
TEST_EMAIL_ALERT=false                  # Set to true to send test email
TEMP_THRESHOLD=55                       # Email alert temperature (°C)
ALERT_DURATION=30                       # Minutes before sending alert
EXCLUDED_DISKS=("/path/device")         # Devices to exclude (Example:"/dev/sdo")

# Color threshold settings (customize as needed)
GREEN_TEMP_MAX=35                # Green for temps up to 35°C
YELLOW_TEMP_MAX=45               # Yellow for temps 35-45°C
                                 # Red for temps above 45°C
```

## Cron Setup

### Health Monitor (Daily @ 4 AM)
Add to crontab for monthly health checks:
```bash
crontab -e
# Add this line for monthly execution on the 1st at 2:00 AM
0 4 * * * /path/to/dhmon.sh                     # Change to path where script is located
```

### Temperature Monitor (Every 5 minutes)
```bash
crontab -e
# Add this line for continuous temperature monitoring
*/5 * * * * /path/to/dtemp_monitor.sh           # Change to path where script is located
```

### Alternative: System-wide cron
Add to `/etc/crontab`:
```bash
# Disk Health Monitoring
0 4 * * * root /path/to/dhmon.sh                # Change to path where script is located
*/5 * * * * root /path/to/dtemp_monitor.sh      # Change to path where script is located
```

## Usage Examples

### Manual Execution
```bash
# Run health check manually
sudo ./dhmon.sh

# Run temperature check manually
sudo ./dtemp_monitor.sh

# Send test email (set TEST_EMAIL_ALERT=true first)
sudo ./dtemp_monitor.sh
```

### Viewing Logs
```bash
# View real-time temperature log with colors
less -R +G /var/log/diskhealth/dtemp.log

# View health monitor log
less +G /var/log/diskhealth/dhmon.log

# View temperature statistics and warnings
less -R +G /var/log/diskhealth/dtemp_stats.log

# Monitor logs in real-time
tail -f /var/log/diskhealth/dtemp.log
```

## Log Examples

### Temperature Log Output
```
[2025-01-15 14:30:01] === Temperature Monitor Started ===
[2025-01-15 14:30:02] TEMP: /dev/sda = 32°C
[2025-01-15 14:30:02] TEMP: /dev/sdb = 41°C
[2025-01-15 14:30:03] TEMP: /dev/sdc = 47°C
[2025-01-15 14:30:03] WARNING: /dev/sdc temperature 47°C over threshold for 5 minutes
[2025-01-15 14:30:03] === Temperature Monitor Completed ===
```

### Statistics Log Output
```
[2025-01-15 00:05:01] STATS: /dev/sda - Min: 28°C, Max: 35°C, Avg: 31°C, Daily Max: 35°C (2025-01-15)
[2025-01-15 00:05:01] STATS: /dev/sdb - Min: 35°C, Max: 44°C, Avg: 39°C, Daily Max: 44°C (2025-01-15)
[2025-01-15 14:30:03] **Warning** /dev/sdc temperature 47°C over threshold
```

### Health Monitor Log Output
```
[2025-01-15 02:00:01] === Disk Health Monitor Started ===
[2025-01-15 02:00:01] Found disks: /dev/sda /dev/sdb /dev/sdc /dev/nvme0n1
[2025-01-15 02:00:01] Monitoring disks: /dev/sda /dev/sdb /dev/sdc /dev/nvme0n1
[2025-01-15 02:00:02] PASSED: /dev/sda health check successful
[2025-01-15 02:00:03] PASSED: /dev/sdb health check successful
[2025-01-15 02:00:04] FAILED: SMART issue detected on /dev/sdc
[2025-01-15 02:00:04] Email alert sent for /dev/sdc
[2025-01-15 02:00:05] === All disks completed health checks ===
```

## Email Alerts

### Email Alert Content Example
```
Subject: Temperature Alert on proxmox-node1: /dev/sdc (58°C)

Disk Temperature Alert
=====================
Hostname: proxmox-node1
Date: Mon Jan 15 14:35:01 CET 2025
Disk: /dev/sdc
Current Temperature: 58°C
Threshold: 55°C
Duration over threshold: 32 minutes

The disk temperature has been above the threshold for more than 30 minutes.
```

### Test Email Function
Enable test emails by setting `TEST_EMAIL_ALERT=true` in the configuration. The script will send a test email on the next execution to verify email functionality.

## File Structure
```
/usr/local/bin/disk-monitoring/
├── dhmon.sh                    # Health monitoring script
└── dtemp_monitor.sh            # Temperature monitoring script

/var/log/diskhealth/
├── dhmon.log                   # Health monitor logs (monthly rotation)
├── dtemp.log                   # Real-time temperature logs (daily rotation)
├── dtemp_stats.log             # Statistics and warnings (weekly retention)
└── state/                      # Script state files
    ├── sda_temp_state          # Temperature alert state
    ├── sda_daily_max           # Daily maximum tracking
    ├── sda_stats               # Temperature statistics
    └── ...                     # (one set per disk)
```

## Troubleshooting

### Common Issues

**No temperature readings (N/A):**
- Verify smartmontools is installed: `which smartctl`
- Check if disk supports temperature monitoring: `smartctl -A /dev/sda | grep -i temp`
- Ensure script has proper permissions to access devices

**Email alerts not working:**
- Check mail configuration: `echo "test" | mail -s "Test" user@domain.com`
- Verify mailutils is installed and configured
- Enable test email mode: `TEST_EMAIL_ALERT=true`

**Color codes not displaying:**
- Use `less -R` command to view colored output
- Check terminal supports ANSI color codes
- Colors are embedded in log files and require proper viewing commands

**Permission denied errors:**
- Run scripts with sudo or as root
- Check file permissions: `ls -la /dev/sd*`
- Ensure log directory permissions: `ls -la /var/log/diskhealth/`

### Debugging

**Enable verbose logging:**
```bash
# Add to script for debugging
set -x  # Enable debug mode
```

**Manual SMART testing:**
```bash
# Test SMART health manually
smartctl -H /dev/sda

# Get temperature manually
smartctl -A /dev/sda | grep -i temp

# Check disk list
lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'
```

## Customization

### Adding More Excluded Disks
```bash
EXCLUDED_DISKS=("/dev/sdo" "/dev/sdb" "/dev/usb_device")
```

### Changing Alert Timing
```bash
TEMP_THRESHOLD=60      # Higher temperature threshold
ALERT_DURATION=60      # Wait 60 minutes before alerting
```

### Custom Color Ranges
```bash
GREEN_TEMP_MAX=30      # Green up to 30°C
YELLOW_TEMP_MAX=50     # Yellow from 30-50°C
                       # Red above 50°C
```

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve these monitoring scripts.

## License

These scripts are provided as-is for educational and operational use in Proxmox environments.

