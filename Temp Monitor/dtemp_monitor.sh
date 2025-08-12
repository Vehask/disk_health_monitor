#!/bin/bash

# Disk Temperature Monitor for Proxmox
# Dependencies: smartmontools, mailutils (optional for email alerts)
# Run every 5 minutes via cron: */5 * * * * /path/to/dtemp-monitor.sh

# Configuration
TEMP_LOGFILE="/var/log/diskhealth/dtemp.log"
STATS_LOGFILE="/var/log/diskhealth/dtemp_stats.log"
STATE_DIR="/var/log/diskhealth/state"
EMAIL_RECIPIENT="admin@yourdomain.com"  # Change this to your email
SEND_EMAIL=true  # Set to false to disable email alerts
TEST_EMAIL_ALERT=false  # Set to true to send a test email alert
TEMP_THRESHOLD=55  # Temperature threshold in Celsius for email alerts
ALERT_DURATION=30  # Minutes to wait before sending alert
EXCLUDED_DISKS=("/dev/sdo")  # Add devices to exclude from monitoring

# Color threshold settings (adjust these values to customize color ranges)
GREEN_TEMP_MAX=40  # Green color for temperatures up to this value (°C)
YELLOW_TEMP_MAX=50  # Yellow color for temperatures between GREEN_TEMP_MAX and this value (°C)
# Red color will be used for temperatures above YELLOW_TEMP_MAX

# Color codes for temperature display
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to get color for temperature
get_temp_color() {
    local temp="$1"
    if [[ "$temp" =~ ^[0-9]+$ ]]; then
        if [[ "$temp" -le "$GREEN_TEMP_MAX" ]]; then
            echo "$GREEN"
        elif [[ "$temp" -le "$YELLOW_TEMP_MAX" ]]; then
            echo "$YELLOW"
        else
            echo "$RED"
        fi
    else
        echo "$NC"
    fi
}

# Function to log with timestamp (for daily logs)
log_temp_message() {
    local message="$1"
    local color="$2"
    if [[ -n "$color" ]]; then
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${color}${message}${NC}" | tee -a "$TEMP_LOGFILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$TEMP_LOGFILE"
    fi
}

# Function to log statistics (for weekly logs)
log_stats_message() {
    local message="$1"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$STATS_LOGFILE"
}

# Function to log warning to stats file
log_stats_warning() {
    local disk="$1"
    local temperature="$2"
    local disk_info_file="$STATE_DIR/$(basename "$disk")_info"
    local temp_color=$(get_temp_color "$temperature")
    
    # Get disk information
    local disk_info="Unknown Unknown - Unknown"
    if [[ -f "$disk_info_file" ]]; then
        disk_info=$(cat "$disk_info_file" 2>/dev/null || echo "Unknown Unknown - Unknown")
    fi
    
    log_stats_message "${RED}**Warning**${NC} $disk -- $disk_info temperature ${temp_color}${temperature}°C${NC} over threshold"
}

# Function to handle daily log rotation (midnight wipe)
handle_daily_rotation() {
    local current_hour=$(date '+%H')
    local current_minute=$(date '+%M')
    
    # If it's close to midnight (00:00-00:05), clear the daily temp log
    if [[ "$current_hour" == "00" && "$current_minute" -lt 6 ]]; then
        if [[ -f "$TEMP_LOGFILE" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Daily log rotation: Clearing previous day's temperature logs ===" > "$TEMP_LOGFILE"
        fi
    fi
}

# Function to handle weekly stats rotation
handle_weekly_stats_rotation() {
    if [[ -f "$STATS_LOGFILE" ]]; then
        # Keep only last 7 days of stats (remove entries older than 7 days)
        local seven_days_ago=$(date -d '7 days ago' '+%Y-%m-%d')
        local temp_file=$(mktemp)
        
        # Keep lines from the last 7 days
        grep -v "^\[" "$STATS_LOGFILE" > "$temp_file" 2>/dev/null || true
        awk -v cutoff="$seven_days_ago" '
        /^\[/ {
            if ($1 "[" $2 >= "[" cutoff) print $0
        }
        !/^\[/ { print $0 }
        ' "$STATS_LOGFILE" >> "$temp_file" 2>/dev/null || true
        
        mv "$temp_file" "$STATS_LOGFILE"
    fi
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v smartctl &> /dev/null; then
        missing_deps+=("smartmontools")
    fi
    
    if ! command -v lsblk &> /dev/null; then
        missing_deps+=("util-linux")
    fi
    
    if [[ "$SEND_EMAIL" == true ]] && ! command -v mail &> /dev/null; then
        log_temp_message "WARNING: mail command not found. Email alerts disabled."
        SEND_EMAIL=false
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_temp_message "ERROR: Missing required dependencies: ${missing_deps[*]}"
        log_temp_message "Install with: apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Function to get disk information (manufacturer, capacity, serial)
get_disk_info() {
    local disk="$1"
    local disk_info
    local manufacturer="Unknown"
    local capacity="Unknown"
    local serial="Unknown"
    
    # Check if disk is accessible
    if [[ ! -e "$disk" ]]; then
        echo "$manufacturer ${capacity} - $serial"
        return 1
    fi
    
    # Get disk information using smartctl
    disk_info=$(smartctl -i "$disk" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$disk_info" ]]; then
        # Extract manufacturer/vendor
        manufacturer=$(echo "$disk_info" | grep -iE "(Vendor|Model Family|Device Model)" | head -1 | sed 's/.*: *//' | awk '{print $1}' | tr -d ',')
        if [[ -z "$manufacturer" || "$manufacturer" == "Unknown" ]]; then
            manufacturer=$(echo "$disk_info" | grep -iE "Model Number" | sed 's/.*: *//' | awk '{print $1}' | tr -d ',')
        fi
        
        # Extract capacity
        capacity=$(echo "$disk_info" | grep -iE "(User Capacity|Total NVM Capacity)" | head -1 | sed 's/.*: *//' | grep -oE '[0-9,.]+ [KMGTPB]+' | head -1)
        if [[ -z "$capacity" ]]; then
            capacity=$(echo "$disk_info" | grep -iE "Capacity" | head -1 | sed 's/.*: *//' | grep -oE '[0-9,.]+ [KMGTPB]+' | head -1)
        fi
        
        # Extract serial number
        serial=$(echo "$disk_info" | grep -iE "Serial [Nn]umber" | sed 's/.*: *//' | tr -d ' ')
        
        # Clean up and format
        [[ -z "$manufacturer" || "$manufacturer" == "" ]] && manufacturer="Unknown"
        [[ -z "$capacity" || "$capacity" == "" ]] && capacity="Unknown"
        [[ -z "$serial" || "$serial" == "" ]] && serial="Unknown"
        
        # Truncate serial if too long
        if [[ ${#serial} -gt 20 ]]; then
            serial="${serial:0:17}..."
        fi
        
        # Format manufacturer and capacity with consistent widths
        if [[ "$manufacturer" != "Unknown" && "$capacity" != "Unknown" ]]; then
            manufacturer=$(printf "%-12s" "$manufacturer")
            capacity=$(printf "%-8s" "$capacity")
        fi
    fi
    
    # Format manufacturer and capacity with dash separator
    if [[ "$manufacturer" != "Unknown" && "$capacity" != "Unknown" ]]; then
        echo "$manufacturer - $capacity - $serial"
    else
        echo "$manufacturer $capacity - $serial"
    fi
    return 0
}

# Function to get disk temperature
get_disk_temperature() {
    local disk="$1"
    local temp_output
    local temperature
    
    # Check if disk is accessible
    if [[ ! -e "$disk" ]]; then
        echo "N/A"
        return 1
    fi
    
    # Get temperature using smartctl
    if [[ "$disk" =~ nvme ]]; then
        # For NVMe drives, look for "Temperature Sensor" or "Composite Temperature"
        temp_output=$(smartctl -A "$disk" 2>/dev/null | grep -iE "(temperature|temp)")
        # Extract temperature from patterns like "41 Celsius" or "Temperature: 41°C" or "41 (0x29)"
        temperature=$(echo "$temp_output" | grep -oE '([0-9]{1,2})\s*(Celsius|°C|\([^)]*\))' | grep -oE '^[0-9]{1,2}' | head -1)
        
        # Alternative parsing for NVMe if first method fails
        if [[ -z "$temperature" ]]; then
            temperature=$(echo "$temp_output" | grep -oE '\b[2-9][0-9]?\b' | head -1)
        fi
    else
        # For SATA/SAS drives, look for Temperature_Celsius or Airflow_Temperature_Cel
        temp_output=$(smartctl -A "$disk" 2>/dev/null | grep -iE "(Temperature_Celsius|Airflow_Temperature_Cel|Temperature)")
        
        # SMART attributes typically show: "194 Temperature_Celsius     0x0022   100   100   000    Old_age   Always       -       41"
        # We want the value at the end (41 in this example)
        temperature=$(echo "$temp_output" | awk '{
            # Look for the last field that looks like a temperature (20-90 range typically)
            for(i=NF; i>=1; i--) {
                if($i ~ /^[2-9][0-9]?$/ && $i >= 20 && $i <= 90) {
                    print $i
                    exit
                }
            }
        }' | head -1)
        
        # Alternative: look for patterns like "Current_Pending_Sector" followed by temperature
        if [[ -z "$temperature" ]]; then
            temperature=$(echo "$temp_output" | grep -oE '\b[2-9][0-9]?\b' | tail -1)
        fi
    fi
    
    # Validate temperature is in reasonable range (20-90°C)
    if [[ -n "$temperature" && "$temperature" =~ ^[0-9]+$ && "$temperature" -ge 20 && "$temperature" -le 90 ]]; then
        echo "$temperature"
        return 0
    else
        echo "N/A"
        return 1
    fi
}

# Function to send email alert
send_temperature_alert() {
    local disk="$1"
    local temperature="$2"
    local duration="$3"
    
    if [[ "$SEND_EMAIL" == true ]]; then
        {
            echo "Disk Temperature Alert"
            echo "====================="
            echo "Hostname: $(hostname)"
            echo "Date: $(date)"
            echo "Disk: $disk"
            echo "Current Temperature: ${temperature}°C"
            echo "Threshold: ${TEMP_THRESHOLD}°C"
            echo "Duration over threshold: ${duration} minutes"
            echo ""
            echo "The disk temperature has been above the threshold for more than $ALERT_DURATION minutes."
        } | mail -s "Temperature Alert on $(hostname): $disk (${temperature}°C)" "$EMAIL_RECIPIENT" 2>> "$TEMP_LOGFILE"
        
        if [[ $? -eq 0 ]]; then
            log_temp_message "Email temperature alert sent for $disk (${temperature}°C)"
        else
            log_temp_message "ERROR: Failed to send email temperature alert for $disk"
        fi
    fi
}

# Function to send test email alert
send_test_email() {
    if [[ "$SEND_EMAIL" == true ]]; then
        {
            echo "Disk Temperature Monitor Test Email"
            echo "=================================="
            echo "Hostname: $(hostname)"
            echo "Date: $(date)"
            echo ""
            echo "This is a test email to verify that the email alert system is working correctly."
            echo "If you receive this email, the disk temperature monitoring email alerts are functioning properly."
            echo ""
            echo "Configuration:"
            echo "- Email Recipient: $EMAIL_RECIPIENT"
            echo "- Temperature Threshold: ${TEMP_THRESHOLD}°C"
            echo "- Alert Duration: ${ALERT_DURATION} minutes"
        } | mail -s "Temperature Monitor Test on $(hostname)" "$EMAIL_RECIPIENT" 2>> "$TEMP_LOGFILE"
        
        if [[ $? -eq 0 ]]; then
            log_temp_message "Test email sent successfully to $EMAIL_RECIPIENT"
        else
            log_temp_message "ERROR: Failed to send test email to $EMAIL_RECIPIENT"
        fi
    else
        log_temp_message "Email alerts are disabled - skipping test email"
    fi
}

# Function to update temperature state and check for alerts
check_temperature_alerts() {
    local disk="$1"
    local temperature="$2"
    local state_file="$STATE_DIR/$(basename "$disk")_temp_state"
    local current_time=$(date '+%s')
    
    if [[ "$temperature" == "N/A" || ! "$temperature" =~ ^[0-9]+$ ]]; then
        # Remove state file if temperature is not available
        [[ -f "$state_file" ]] && rm -f "$state_file"
        return
    fi
    
    if [[ "$temperature" -gt "$TEMP_THRESHOLD" ]]; then
        # Temperature is over threshold
        if [[ -f "$state_file" ]]; then
            # Read existing state
            local start_time=$(cat "$state_file" 2>/dev/null || echo "$current_time")
        else
            # Create new state file
            echo "$current_time" > "$state_file"
            local start_time="$current_time"
        fi
        
        # Calculate duration in minutes
        local duration=$(( (current_time - start_time) / 60 ))
        
        # Log warning to stats file for temperatures over threshold
        log_stats_warning "$disk" "$temperature"
        
        # Check if we should send an alert
        if [[ "$duration" -ge "$ALERT_DURATION" ]]; then
            # Check if we've already sent an alert for this episode
            local alert_sent_file="$STATE_DIR/$(basename "$disk")_alert_sent"
            if [[ ! -f "$alert_sent_file" ]]; then
                send_temperature_alert "$disk" "$temperature" "$duration"
                echo "$current_time" > "$alert_sent_file"
                log_temp_message "ALERT: $disk temperature ${temperature}°C over threshold for ${duration} minutes" "$RED"
            fi
        else
            log_temp_message "WARNING: $disk temperature ${temperature}°C over threshold for ${duration} minutes" "$YELLOW"
        fi
    else
        # Temperature is normal, remove state files
        [[ -f "$state_file" ]] && rm -f "$state_file"
        [[ -f "$STATE_DIR/$(basename "$disk")_alert_sent" ]] && rm -f "$STATE_DIR/$(basename "$disk")_alert_sent"
    fi
}

# Function to update temperature statistics
update_temperature_stats() {
    local disk="$1"
    local temperature="$2"
    local disk_info="$3"
    local stats_file="$STATE_DIR/$(basename "$disk")_stats"
    local daily_max_file="$STATE_DIR/$(basename "$disk")_daily_max"
    local disk_info_file="$STATE_DIR/$(basename "$disk")_info"
    local current_date=$(date '+%Y-%m-%d')
    
    if [[ "$temperature" == "N/A" || ! "$temperature" =~ ^[0-9]+$ ]]; then
        return
    fi
    
    # Store disk info for stats logging
    echo "$disk_info" > "$disk_info_file"
    
    # Add temperature to daily stats
    echo "$temperature" >> "$stats_file"
    
    # Update daily maximum temperature
    if [[ -f "$daily_max_file" ]]; then
        local last_date=$(head -1 "$daily_max_file" 2>/dev/null | cut -d' ' -f1)
        local last_max=$(head -1 "$daily_max_file" 2>/dev/null | cut -d' ' -f2)
        
        if [[ "$last_date" == "$current_date" ]]; then
            # Same day - update max if current temp is higher
            if [[ "$temperature" -gt "$last_max" ]]; then
                echo "$current_date $temperature" > "$daily_max_file"
            fi
        else
            # New day - start with current temperature as max
            echo "$current_date $temperature" > "$daily_max_file"
        fi
    else
        # First reading - create daily max file
        echo "$current_date $temperature" > "$daily_max_file"
    fi
    
    # Keep only last 24 hours of readings (288 readings for 5-minute intervals)
    if [[ -f "$stats_file" ]]; then
        tail -n 288 "$stats_file" > "$stats_file.tmp" && mv "$stats_file.tmp" "$stats_file"
    fi
}

# Function to handle daily statistics update (called at midnight)
handle_daily_stats_update() {
    local current_hour=$(date '+%H')
    local current_minute=$(date '+%M')
    local current_date=$(date '+%Y-%m-%d')
    local stats_flag_file="$STATE_DIR/daily_stats_completed_$current_date"
    
    # Only run stats once per day at midnight (00:00-00:05) and if not already completed today
    if [[ "$current_hour" == "00" && "$current_minute" -lt 6 && ! -f "$stats_flag_file" ]]; then
        # Add daily separator to stats log
        log_stats_message ""
        log_stats_message "==================== Daily Statistics for $current_date ===================="
        
        # Get list of disks to process stats for
        local all_disks
        all_disks=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
        
        # Filter out excluded disks
        local disks=""
        for disk in $all_disks; do
            local exclude=false
            for excluded in "${EXCLUDED_DISKS[@]}"; do
                if [[ "$disk" == "$excluded" ]]; then
                    exclude=true
                    break
                fi
            done
            if [[ "$exclude" == false ]]; then
                disks="$disks $disk"
            fi
        done
        
        # Remove leading space
        disks=$(echo "$disks" | xargs)
        
        # Calculate stats for each disk
        for disk in $disks; do
            local stats_file="$STATE_DIR/$(basename "$disk")_stats"
            local daily_max_file="$STATE_DIR/$(basename "$disk")_daily_max"
            if [[ -f "$stats_file" && -s "$stats_file" ]]; then
                calculate_and_log_daily_stats "$disk" "$stats_file" "$daily_max_file"
            fi
        done
        
        # Create flag file to prevent duplicate stats for today
        touch "$stats_flag_file"
        
        # Clean up old flag files (older than 3 days)
        find "$STATE_DIR" -name "daily_stats_completed_*" -mtime +3 -delete 2>/dev/null || true
    fi
}

# Function to calculate and log daily statistics
calculate_and_log_daily_stats() {
    local disk="$1"
    local stats_file="$2"
    local daily_max_file="$3"
    local disk_info_file="$STATE_DIR/$(basename "$disk")_info"
    
    if [[ ! -f "$stats_file" || ! -s "$stats_file" ]]; then
        return
    fi
    
    # Get disk information
    local disk_info="Unknown Unknown - Unknown"
    if [[ -f "$disk_info_file" ]]; then
        disk_info=$(cat "$disk_info_file" 2>/dev/null || echo "Unknown Unknown - Unknown")
    fi
    
    # Calculate statistics for the day
    local temps=($(cat "$stats_file"))
    local min_temp=${temps[0]}
    local max_temp=${temps[0]}
    local sum=0
    local count=${#temps[@]}
    
    for temp in "${temps[@]}"; do
        if [[ "$temp" -lt "$min_temp" ]]; then
            min_temp="$temp"
        fi
        if [[ "$temp" -gt "$max_temp" ]]; then
            max_temp="$temp"
        fi
        sum=$((sum + temp))
    done
    
    local avg_temp=$((sum / count))
    
    # Get colors for each temperature value
    local min_color=$(get_temp_color "$min_temp")
    local max_color=$(get_temp_color "$max_temp")
    local avg_color=$(get_temp_color "$avg_temp")
    
    # Format disk name for consistent alignment (16 characters)
    local formatted_disk=$(printf "%-16s" "$disk")
    
    # Split disk info into manufacturer/capacity and serial for better formatting
    # Handle the new format: "Manufacturer - Capacity - Serial"
    local manufacturer_capacity
    local serial
    
    if [[ "$disk_info" =~ ^(.+)\ -\ (.+)\ -\ (.+)$ ]]; then
        # Three-part format: "Manufacturer - Capacity - Serial"
        manufacturer_capacity="${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}"
        serial="${BASH_REMATCH[3]}"
    else
        # Fallback for two-part format: "Manufacturer Capacity - Serial"
        manufacturer_capacity=$(echo "$disk_info" | sed 's/ - [^-]*$//')
        serial=$(echo "$disk_info" | sed 's/.* - //')
    fi
    
    # Format manufacturer/capacity (24 characters) and serial (20 characters)
    local formatted_mfg_cap=$(printf "%-24s" "$manufacturer_capacity")
    local formatted_serial=$(printf "%-20s" "$serial")
    
    # Log daily statistics with improved formatting
    log_stats_message "STATS: ${formatted_disk} -- ${formatted_mfg_cap} - ${formatted_serial}  - Min: ${min_color}${min_temp}°C${NC}, Max: ${max_color}${max_temp}°C${NC}, Avg: ${avg_color}${avg_temp}°C${NC}"
}

# Main execution
main() {
    local exit_code=0
    
    # Create directories if they don't exist
    mkdir -p "$(dirname "$TEMP_LOGFILE")"
    mkdir -p "$(dirname "$STATS_LOGFILE")"
    mkdir -p "$STATE_DIR"
    
    # Handle log rotations
    handle_daily_rotation
    handle_weekly_stats_rotation
    
    # Handle daily statistics update (at midnight)
    handle_daily_stats_update
    
    # Start logging with blue color
    log_temp_message "=== Temperature Monitor Started ===" "$BLUE"
    
    # Send test email if enabled
    if [[ "$TEST_EMAIL_ALERT" == true ]]; then
        log_temp_message "Sending test email alert..." "$BLUE"
        send_test_email
    fi
    
    # Check dependencies
    check_dependencies
    
    # Get list of physical disks
    local all_disks
    all_disks=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
    
    if [[ -z "$all_disks" ]]; then
        log_temp_message "ERROR: No disks found" "$RED"
        exit 1
    fi
    
    # Filter out excluded disks
    local disks=""
    for disk in $all_disks; do
        local exclude=false
        for excluded in "${EXCLUDED_DISKS[@]}"; do
            if [[ "$disk" == "$excluded" ]]; then
                exclude=true
                break
            fi
        done
        if [[ "$exclude" == false ]]; then
            disks="$disks $disk"
        fi
    done
    
    # Remove leading space
    disks=$(echo "$disks" | xargs)
    
    if [[ -z "$disks" ]]; then
        log_temp_message "ERROR: No disks to monitor after exclusions" "$RED"
        exit 1
    fi
    
    # Monitor each disk
    for disk in $disks; do
        local temperature
        local disk_info
        temperature=$(get_disk_temperature "$disk")
        disk_info=$(get_disk_info "$disk")
        
        # Format disk name for consistent alignment (16 characters)
        local formatted_disk=$(printf "%-16s" "$disk")
        
        # Split disk info into manufacturer/capacity and serial for better formatting
        # Handle the new format: "Manufacturer - Capacity - Serial"
        local manufacturer_capacity
        local serial
        
        if [[ "$disk_info" =~ ^(.+)\ -\ (.+)\ -\ (.+)$ ]]; then
            # Three-part format: "Manufacturer - Capacity - Serial"
            manufacturer_capacity="${BASH_REMATCH[1]} - ${BASH_REMATCH[2]}"
            serial="${BASH_REMATCH[3]}"
        else
            # Fallback for two-part format: "Manufacturer Capacity - Serial"
            manufacturer_capacity=$(echo "$disk_info" | sed 's/ - [^-]*$//')
            serial=$(echo "$disk_info" | sed 's/.* - //')
        fi
        
        # Format manufacturer/capacity (24 characters) and serial (20 characters)
        local formatted_mfg_cap=$(printf "%-24s" "$manufacturer_capacity")
        local formatted_serial=$(printf "%-20s" "$serial")
        
        if [[ "$temperature" != "N/A" ]]; then
            local temp_color=$(get_temp_color "$temperature")
            log_temp_message "TEMP: ${formatted_disk} -- ${formatted_mfg_cap} - ${formatted_serial}  = ${temperature}°C" "$temp_color"
            check_temperature_alerts "$disk" "$temperature"
            update_temperature_stats "$disk" "$temperature" "$disk_info"
        else
            log_temp_message "TEMP: ${formatted_disk} -- ${formatted_mfg_cap} - ${formatted_serial}  = N/A (unable to read temperature)" "$NC"
        fi
    done
    
    # End logging with blue color
    log_temp_message "=== Temperature Monitor Completed ===" "$BLUE"
    
    exit $exit_code
}

# Execute main function
main "$@"