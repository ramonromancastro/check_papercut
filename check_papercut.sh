#!/bin/sh

# check_papercut check PaperCut server status.
# Copyright (C) 2019  Ramón Román Castro <ramonromancastro@gmail.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

# DEPENDENCIES

# - curl
# - jq
# - printf

# CONSTANTS

version=0.4.0
plugin=check_papercut.sh

# job-ticketing/status
# license/status
# mobility-print-servers/status
# print-providers/status
# printers/status
# site-servers/status
# web-print/status
# application-server/status
# database/status
# devices/status

api_url="/api/health/"
availables_status="database,devices,job-ticketing,license,mobility-print-servers,print-providers,printers,site-servers,web-print"

# GLOBAL VARIABLES

## NAGIOS VARIABLES

nagios_ok=0
nagios_warning=1
nagios_critical=2
nagios_unknown=3
nagios_text=("OK" "WARNING" "CRITICAL" "UNKNOWN")

plugin_hostname=localhost
plugin_protocol=http
plugin_port=9191
plugin_authentication=
plugin_timeout=5
plugin_warning=1
plugin_critical=1
plugin_days=30
plugin_authentication=
plugin_verbose=0
plugin_status=

plugin_problems=0

plugin_returnCode=${NAGIOS_OK}
plugin_returnMessage=
plugin_returnDetails=()
plugin_returnPerfData=()

# FUNCTIONS

verbose(){
	level=$1
	message=$2
	if [ $plugin_verbose -ge $level ]; then
		echo $message
	fi
}

getparams(){
	if [ $# -eq 0 ]; then
		shortusage
		exit ${nagios_unknown};
	fi
	while [[ $# -gt 0 ]]; do
		key="$1"
		case $key in
			--hostname|-H)
				shift
				plugin_hostname=$1
				;;
			--secure|-s)
				plugin_protocol=https
				;;
			--port|-p)
				shift
				plugin_port=$1
				;;
			--authentication|-a)
				shift
				plugin_authentication=$1
				;;
			--timeout|-t)
				shift
				plugin_timeout=$1
				;;
			--warning|-w)
				shift
				plugin_warning=$1
				;;
			--critical|-w)
				shift
				plugin_critical=$1
				;;
			--status|-S)
				shift
				plugin_status=$1
				;;
			--days|-d)
				shift
				plugin_days=$1
				;;
			--verbose|-v)
				plugin_verbose=1
				;;
			--version|-V)
				version
				exit ${nagios_ok};
				;;
			--help)
				usage
				exit ${nagios_ok};
				;;
			*)
				usage
				exit ${nagios_unknown};
				;;
		esac
		shift
	done
}

version(){
	echo "${plugin} ${version} (rrc2software)"
}

shortusage(){
	cat << EOF
${plugin}: try '${plugin} --help' for more information
EOF
}

usage(){
	cat << EOF
Usage: ${plugin} options...
Options:
 -H, --hostname <host>  PaperCut host
 -s, --secure        Use HTTPS
 -p, --port <port>   PaperCut port
 -a, --authentication <auth>  PaperCut authorization key
 -t, --timeout <seconds>  Maximum time allowed for connection
 -S, --status <value>  Item status. If none specified,
                       global status is tested
 -w, --warning <value>  Warning interval
 -c, --critical <value>  Critical interval
 -d, --days <days>   License remaining days
 -v, --verbose       Make the operation more talkative  
 -V, --version       Show version number and quit
 -h, --help          This help text
 
Notes
 Item status availables are:
   $availables_status
EOF
}

# MAIN CODE

verbose 1 "Parsing parameters"
getparams "$@"

url_health_summary="${plugin_protocol}://${plugin_hostname}:${plugin_port}${api_url}?Authorization=${plugin_authentication}"

verbose 1 "Getting server status from $url_health_summary"
json_response=$(curl --connect-timeout ${plugin_timeout} --silent --insecure ${url_health_summary} 2> /dev/null)

verbose 1 "Parsing server status"
database_status=$(echo $json_response | jq -r ".database.status")
devices_inErrorCount=$(echo $json_response | jq -r ".devices.inErrorCount")
jobTicketing_status=$(echo $json_response | jq -r ".jobTicketing.status.status")
jobTicketing_message=$(echo $json_response | jq -r ".jobTicketing.status.message")
license_upgradeAssuranceRemainingDays=$(echo $json_response | jq -r ".license.upgradeAssuranceRemainingDays")
mobilityPrintServers_offlineCount=$(echo $json_response | jq -r ".mobilityPrintServers.offlineCount")
printProviders_offlineCount=$(echo $json_response | jq -r ".printProviders.offlineCount")
printers_inErrorCount=$(echo $json_response | jq -r ".printers.inErrorCount")
siteServers_offlineCount=$(echo $json_response | jq -r ".siteServers.offlineCount")
webPrint_offlineCount=$(echo $json_response | jq -r ".webPrint.offlineCount")

verbose 1 "Checking server status"

## Database
if [ -z $plugin_status ] || [ "$plugin_status" == "database" ]; then
	if [ "${database_status}" != "OK" ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Database.status: ${database_status}")
	fi
fi

## Devices
if [ -z $plugin_status ] || [ "$plugin_status" == "devices" ]; then
	if [ "${devices_inErrorCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Devices.errorCount: ${devices_inErrorCount}")
	fi
	plugin_returnPerfData+=("'devices_inErrorCount'=${devices_inErrorCount};1")
fi

## Job Ticketing
if [ -z $plugin_status ] || [ "$plugin_status" == "job-ticketing" ]; then
	if [ "${jobTicketing_status}" != "OK" ] && [ "${jobTicketing_message}" != "Job Ticketing is not installed." ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Job Ticketing.status: ${jobTicketing_message}")
	fi
fi

## License
if [ -z $plugin_status ] || [ "$plugin_status" == "license" ]; then
	if [ "${license_upgradeAssuranceRemainingDays}" -le "${plugin_days}" ]; then
		((plugin_problems++))
		plugin_returnDetails+=("License.remainingDays: ${license_upgradeAssuranceRemainingDays}")
	fi
	plugin_returnPerfData+=("'license_upgradeAssuranceRemainingDays'=${license_upgradeAssuranceRemainingDays};${plugin_days}:")
fi

## Mobility Print Servers
if [ -z $plugin_status ] || [ "$plugin_status" == "mobility-print-servers" ]; then
	if [ "${mobilityPrintServers_offlineCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Mobility Print Servers.offlineCount: ${mobilityPrintServers_offlineCount}")
	fi
	plugin_returnPerfData+=("'mobilityPrintServers_offlineCount'=${mobilityPrintServers_offlineCount};1")
fi

## Print Providers
if [ -z $plugin_status ] || [ "$plugin_status" == "print-providers" ]; then
	if [ "${printProviders_offlineCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Print Providers.offlineCount: ${printProviders_offlineCount}")
	fi
	plugin_returnPerfData+=("'printProviders_offlineCount'=${printProviders_offlineCount};1")
fi

## Printers
if [ -z $plugin_status ] || [ "$plugin_status" == "printers" ]; then
	if [ "${printers_inErrorCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Printers.errorCount: ${printers_inErrorCount}")
	fi
	plugin_returnPerfData+=("'printers_inErrorCount'=${printers_inErrorCount};1")
fi

## Site Servers
if [ -z $plugin_status ] || [ "$plugin_status" == "site-servers" ]; then
	if [ "${siteServers_offlineCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Site Servers.offlineCount: ${siteServers_offlineCount}")
	fi
	plugin_returnPerfData+=("'siteServers_offlineCount'=${siteServers_offlineCount};1")
fi

## Web Print
if [ -z $plugin_status ] || [ "$plugin_status" == "web-print" ]; then
	if [ "${webPrint_offlineCount}" -ne 0 ]; then
		((plugin_problems++))
		plugin_returnDetails+=("Web Print.offlineCount: ${webPrint_offlineCount}")
	fi
	plugin_returnPerfData+=("'webPrint_offlineCount'=${webPrint_offlineCount};1")
fi

## Write plugin reponse
if [ "${plugin_problems}" -gt 0 ]; then
	plugin_returnCode=${nagios_warning}
	if [ "${plugin_problems}" -ge "${plugin_critical}" ]; then plugin_returnCode=${nagios_critical}; fi
	plugin_returnMessage="${plugin_problems} problems detected."
else
	plugin_returnMessage="All components are ok."
fi

printf '%s: %s\n' "${nagios_text[${plugin_returnCode}]}" "${plugin_returnMessage}"
if [ "${plugin_problems}" -gt 0 ]; then
	printf '%s\n' "${plugin_returnDetails[@]}"
fi
echo -n "|"
printf '%s ' "${plugin_returnPerfData[@]}"
exit ${plugin_returnCode}
