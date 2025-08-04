Scripts for use in Proxmox Node to monitor S.M.A.R.T. health and temperature for HDDs/SSDs with e-mail alerts.

Scripts are run as a cron job and will append to logfiles located in **/var/log/diskhealth/**. 

Disk health monitor appends to **dhmon.log**.

Temp monitor appends to **dtemp.log** and **dtemp_stats.log**. 
Command 'less -R +G /path/to/logfile.log' allows for color-coded output (-R) and displays from the bottom of the logfile (+G):
 - **Green:** Below 35 degrees celsius
 - **Yellow:** Between 35-45 degrees celsius
 - **Red:** Above 45 degrees celsius
 - **Blue:** Start/completion messages ("=== Temperature Monitor Started/Completed ===")
   - **dtemp.log**         contains entries for readings done at set intervals (intervals are set in /etc/crontab) and overwrites daily.
   - **dtemp_stats.log**   contains entries for daily Min/Max/Avg, as well as warnings for readings above 55 degrees. New log entries are made at midnight and entries older than 7 days are deleted.

**README will be updated soon**

