#!/bin/bash
set -euo pipefail

usage() {
	echo "usage: $(basename "$0") [-a <application name>][-d <dns name>][-e <standard out path>][-f <standard error path>][-i <ip address>][-l <label>][-o <hostname>][-n <application name>][-p <port number>][-s <service name>][-t <transmission protocol>][-k][-r][-v|-vv][-h]"
}

add_etc_hosts_entry()
{
	local ipAddress=${1:?add_etc_hosts_entry: IP Address is missing at position 1.}
	local hostName=${2:?add_etc_hosts_entry: Hostname is missing at position 2.}

	if grep -E "^${ipAddress}[[:space:]]+$hostName$" "$ETC_HOSTS_PATH" >/dev/null 2>&1; then
		LOG_WARN "Entry Already Exists. Skipping Entry."
	else
		sudo cp "$ETC_HOSTS_PATH" "$ETC_HOSTS_PATH.bak.$(date +%Y%m%d_%H%M%S)"
		printf '%s\t%s\n' "$hostName" "$ipAddress" | sudo tee -a "$ETC_HOSTS_PATH" >/dev/null
	fi
	
	exit "$EXIT_OK"
}

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ScriptDir/00_SharedConstantsAndFunctions.sh"

Label=""
HostName=""
DomainName=""
ApplicationLayer=""
ServiceName=""
TransportLayer=""
PortNumber=""
IpAddress=""
RunAtLoad=false
KeepAlive=false
StandardOutPath=""
StandardErrorPath=""

while getopts "a:d:e:f:i:l:o:p:s:t:krhv" opt; do
	case "$opt" in
		a) ApplicationLayer="$(echo "${OPTARG// /}" | tr "[:upper:]" "[:lower:]")" ;;
		d) DomainName=${OPTARG// /} ;;
		e) StandardErrorPath=${OPTARG// /} ;;
		f) StandardOutPath=${OPTARG// /} ;;
		i) IpAddress="${OPTARG// /}" ;;
		k) KeepAlive=true ;;
		l) Label="${OPTARG// /}" ;;
		o) HostName="${OPTARG// /}" ;;
		p) PortNumber="${OPTARG// /}" ;;
		r) RunAtLoad=true ;;
		s) ServiceName="$(echo "${OPTARG}" | tr "[:upper:]" "[:lower:]")" ;;
		t) TransportLayer="$(echo "${OPTARG// /}" | tr "[:upper:]" "[:lower:]")" ;;
		h) usage; exit "$EXIT_OK" ;;
		v) ((LOG_LEVEL++)) ;;
		\?) echo "Unknown Flag: -$OPTARG" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;
		:) echo "Flag -$OPTARG Requires A Value" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;
	esac
done
shift $((OPTIND - 1))

if [[ -z "$HostName" ]]; then
	LOG_ERROR "Hostname (-o) is required."
	usage >&2
	exit "$EXIT_USAGE_ERROR"
fi

if [[ -z "$IpAddress" ]]; then
	LOG_ERROR "IP Address (-i) is required."
	usage >&2
	exit "$EXIT_USAGE_ERROR"
else
	LOG_STEP "Validating IP Address."
	if [[ "$IpAddress" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
		LOG_SUCCESS "IP Address: '$IpAddress' is valid."
	else
		LOG_ERROR "IP Address: '$IpAddress' is malformed. IP Address needs to be an IPv4 address."
		exit "$EXIT_USAGE_ERROR"
	fi 
fi

PythonExit=0
PythonStdOut=""
PythonStdErr=""

LOG_STEP "Creating DNS Record On '$KERNEL'."

if [[ "$KERNEL" == "darwin" ]]; then
	LOG_VERBOSE "Checking if Label, Domain Name, Service Name, Application Layer, Transport Layer, Port Number, IP Address, Run At Load, Keep Alive, Standard Out Path & Standard Error Path are provided."
	if [[ -n "$Label" && -n "$HostName" && -n "$DomainName" && -n "$ServiceName" && -n "$ApplicationLayer" && -n "$TransportLayer" && -n "$PortNumber" && -n "$IpAddress" && -n "$RunAtLoad" && -n "$KeepAlive" && -n "$StandardOutPath" && -n "$StandardErrorPath" ]]; then

		LOG_VERBOSE "Checking if dns-sd service is running with the provided config."
		if pgrep -fl "^/usr/bin/dns-sd -P $ServiceName _$ApplicationLayer\._$TransportLayer $DomainName $PortNumber $HostName $IpAddress$" >/dev/null 2>&1; then
			LOG_STEP "dns-sd service is running, checking if file exists before stopping dns-sd service."
			if [[ -f "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist" ]]; then
				sudo launchctl unload "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist"
				LOG_SUCCESS "dns-sd service is no longer running."
			else
				LOG_ERROR "The label '$Label' which is also used as the file name, does not exist."
				exit "$EXIT_USAGE_ERROR"
			fi
		fi
		LOG_STEP "Checking dns-sd service running or not is completed."

		LOG_VERBOSE "Checking if the file exists for deletion."
		if [[ -f "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist" ]]; then
			LOG_STEP "Deleting plist file from Launch Daemons Directory."
			sudo rm -f "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist"
			LOG_SUCCESS "Deleting plist file from Launch Daemons Directory is now completed."
		fi 

		LOG_VERBOSE "Building up arguments for executing Python script."
		pythonArgs=(
			"$ScriptDir/04_GenerateDNSDaemonEntry.py"
			-l "$Label"
			-s "$ServiceName"
			-a "$ApplicationLayer"
			-t "$TransportLayer"
			-d "$DomainName"
			-p "$PortNumber"
			-o "$HostName"
			-e "$StandardErrorPath"
			-f "$StandardOutPath"
			-i "$IpAddress"
		)

		LOG_VERBOSE "Setting Run At Load flag."
		if [ "$RunAtLoad" = true ]; then
			pythonArgs+=(--run-at-load)
		else
			pythonArgs+=(--no-run-at-load)
		fi

		LOG_VERBOSE "Setting Keep Alive flag."
		if [ "$KeepAlive" = true ]; then
			PythonArgs+=(--keep-alive)
		else
			PythonArgs+=(--no-keep-alive)
		fi
		LOG_DEBUG "Python arguments:\n${pythonArgs[*]}"

		LOG_STEP "Executing Python code to generate plist."
		PythonStdOut=$(python3 "${pythonArgs[@]}" 2>/tmp/04_GenerateDNSDaemonEntry.$$.stderr) || PythonExit=$?
		PythonStdErr=$(cat /tmp/04_GenerateDNSDaemonEntry.$$.stderr; rm -f /tmp/04_GenerateDNSDaemonEntry.$$.stderr)

		LOG_DEBUG "Python Exit Code: '$PythonExit'"
		LOG_DEBUG "Python Standard Out:\n'$PythonStdOut'"
		LOG_DEBUG "Python Standard Error: '$PythonStdErr'"

		LOG_VERBOSE "Validating Python script execution output."
		if [[ -n $PythonStdErr ]]; then
			LOG_ERROR "python error: $PythonStdErr"
			exit "$EXIT_ENV_ERROR"
		elif [[ $PythonExit -eq 0 && -n $PythonStdOut ]]; then
			LOG_STEP "Storing Python Script plist output into Launch Daemon directory."
			echo "$PythonStdOut" | sudo tee "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist" >/dev/null
			LOG_SUCCESS "Storing output plist from Python script into Launch Daemon directory is completed."

			LOG_STEP "Launching dns-sd service."
			sudo launchctl load "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist"
			LOG_SUCCESS "Launching dns-sd service successful."
			exit "$EXIT_OK"
		else
			LOG_ERROR "python exited with unexpected code: $PythonExit"
			exit "$EXIT_ENV_ERROR"
		fi
	elif [[ -n "$HostName" && -n "$IpAddress" && -z "$Label" && -z "$DomainName" && -z "$ServiceName" && -z "$ApplicationLayer" && -z "$TransportLayer" && -z "$PortNumber" && -z "$StandardOutPath" && -z "$StandardErrorPath" ]]; then
		LOG_STEP "Adding entry in /etc/hosts file."
		add_etc_hosts_entry "$IpAddress" "$HostName"
	else
		LOG_ERROR "Either provide all required input for dns-sd server or just provide Host name and IP address for entry /etc/hosts file."
		exit "$EXIT_USAGE_ERROR"
	fi
fi