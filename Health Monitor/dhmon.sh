#!/bin/bash

# Disk Health Monitor for Proxmox
# Dependencies: smartmontools, mailutils (optional for email alerts)

# Configuration
LOGFILE="/var/log/diskhealth/dhmon.log"
EMAIL_RECIPIENT="CHANGE-TO@YOUR.EMAIL"  # Change this to your email
SEND_EMAIL=true  # Set to false to disable email alerts
TEST_EMAIL_ALERT=false  # Set to true to send a test email alert
EXCLUDED_DISKS=("/dev/sdo")  # Add devices to exclude from monitoring

# Function to handle monthly log rotation
handle_log_rotation() {
    local current_day=$(date '+%d')
    
    # If it's the 1st of the month, clear the log file
    if [[ "$current_day" == "01" ]]; then
        if [[ -f "$LOGFILE" ]]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Monthly log rotation: Clearing previous month's logs ===" > "$LOGFILE"
        fi
    fi
}

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
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
        log_message "WARNING: mail command not found. Email alerts disabled."
        SEND_EMAIL=false
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_message "ERROR: Missing required dependencies: ${missing_deps[*]}"
        log_message "Install with: apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Function to send email alert
send_alert() {
    local disk="$1"
    local health_output="$2"
    
    if [[ "$SEND_EMAIL" == true ]]; then
        {
            echo "SMART Health Check Alert"
            echo "========================"
            echo "Hostname: $(hostname)"
            echo "Date: $(date)"
            echo "Disk: $disk"
            echo ""
            echo "SMART Output:"
            echo "$health_output"
        } | mail -s "SMART Alert on $(hostname): $disk" "$EMAIL_RECIPIENT" 2>> "$LOGFILE"
        
        if [[ $? -eq 0 ]]; then
            log_message "Email alert sent for $disk"
        else
            log_message "ERROR: Failed to send email alert for $disk"
        fi
    fi
}

# Function to send test email alert
send_test_email() {
    if [[ "$SEND_EMAIL" == true ]]; then
        {
            echo "Disk Health Monitor Test Email"
            echo "=============================="
            echo "Hostname: $(hostname)"
            echo "Date: $(date)"
            echo ""
            echo "This is a test email to verify that the health monitoring email alert system is working correctly."
            echo "If you receive this email, the disk health monitoring email alerts are functioning properly."
            echo ""
            echo "Configuration:"
            echo "- Email Recipient: $EMAIL_RECIPIENT"
            echo "- Monitoring Excluded Disks: ${EXCLUDED_DISKS[*]}"
        } | mail -s "Health Monitor Test on $(hostname)" "$EMAIL_RECIPIENT" 2>> "$LOGFILE"
        
        if [[ $? -eq 0 ]]; then
            log_message "Test email sent successfully to $EMAIL_RECIPIENT"
        else
            log_message "ERROR: Failed to send test email to $EMAIL_RECIPIENT"
        fi
    else
        log_message "Email alerts are disabled - skipping test email"
    fi
}

# Function to check disk health
check_disk_health() {
    local disk="$1"
    local health_output
    local health_status
    
    log_message "Checking disk: $disk"
    
    # Check if disk is accessible
    if [[ ! -e "$disk" ]]; then
        log_message "ERROR: Disk $disk not accessible"
        return 1
    fi
    
    # Use appropriate flags depending on device type
    if [[ "$disk" =~ nvme ]]; then
        health_output=$(smartctl -H "$disk" 2>&1)
    else
        health_output=$(smartctl -H -d auto "$disk" 2>&1)
    fi
    
    # Check if smartctl command succeeded
    if [[ $? -ne 0 ]]; then
        log_message "ERROR: smartctl failed for $disk"
        log_message "Output: $health_output"
        return 1
    fi
    
    # Check health status - look for various healthy indicators
    if echo "$health_output" | grep -qE "(PASSED|OK|GOOD|HEALTHY)"; then
        log_message "PASSED: $disk health check successful"
        return 0
    else
        log_message "FAILED: SMART issue detected on $disk"
        log_message "SMART Output: $health_output"
        send_alert "$disk" "$health_output"
        return 1
    fi
}

# Main execution
main() {
    local exit_code=0
    local failed_disks=()
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOGFILE")"
    
    # Handle monthly log rotation
    handle_log_rotation
    
    # Start logging
    log_message "=== Disk Health Monitor Started ==="
    
    # Send test email if enabled
    if [[ "$TEST_EMAIL_ALERT" == true ]]; then
        log_message "Sending test email alert..."
        send_test_email
    fi
    
    # Check dependencies
    check_dependencies
    
    # Get list of physical disks
    local all_disks
    all_disks=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}')
    
    if [[ -z "$all_disks" ]]; then
        log_message "ERROR: No disks found"
        exit 1
    fi
    
    # Filter out excluded disks
    local disks=""
    for disk in $all_disks; do
        local exclude=false
        for excluded in "${EXCLUDED_DISKS[@]}"; do
            if [[ "$disk" == "$excluded" ]]; then
                log_message "Excluding disk: $disk (configured in EXCLUDED_DISKS)"
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
        log_message "ERROR: No disks to monitor after exclusions"
        exit 1
    fi
    
    log_message "Found disks: $all_disks"
    log_message "Monitoring disks: $disks"
    
    # Check each disk
    for disk in $disks; do
        if ! check_disk_health "$disk"; then
            failed_disks+=("$disk")
            exit_code=1
        fi
    done
    
    # Summary
    if [[ ${#failed_disks[@]} -eq 0 ]]; then
        log_message "=== All disks passed health checks ==="
    else
        log_message "=== WARNING: ${#failed_disks[@]} disk(s) failed health checks: ${failed_disks[*]} ==="
    fi
    
    log_message "=== Disk Health Monitor Completed ==="
    
    exit $exit_code
}

# Execute main function
main "$@"