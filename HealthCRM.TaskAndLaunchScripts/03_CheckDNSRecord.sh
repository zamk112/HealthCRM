#!/bin/bash
set -euo pipefail

usage() {
	echo "usage: $(basename "$0") [-a <application name>][-d <dns name>][-i <ip address>][-n <application name>][-p <port number>][-t <transmission protocol>][-v|-vv][-h]"
}

check_etc_hosts()
{
	local ipAddress=$1
	local hostName=$2
	if grep -E "^${ipAddress}[[:space:]]+$hostName$" "/etc/hosts" >/dev/null 2>&1; then
		LOG_SUCCESS "DNS entry in /etc/hosts file detected."
		exit "${EXIT_OK}"
	else
		LOG_WARN "DNS entry for $hostName is not bound to any particular service."
		exit "${EXIT_MISSING_DNS_ENTRY}"
	fi
}

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ScriptDir/00_SharedConstantsAndFunctions.sh"

HostName=""
DomainName=""
ApplicationLayer=""
ServiceName=""
TransportLayer=""
PortNumber=""
IpAddress=""

pgrepExit=0
pgrepStdOut=""
pgrepStdErr=""

while getopts "a:o:d:i:p:s:t:hv" opt; do
	case "$opt" in
		a) ApplicationLayer="${OPTARG// /}" ;;
		o) HostName="${OPTARG// /}" ;;
		d) DomainName=${OPTARG// /} ;;
		i) IpAddress="${OPTARG// /}" ;;
		s) ServiceName="${OPTARG}" ;;
		p) PortNumber="${OPTARG// /}" ;;
		t) TransportLayer="${OPTARG// /}" ;;
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
fi

LOG_STEP "Checking DNS Record On '$KERNEL'."

if [[ "$KERNEL" == "darwin" ]]; then 
	if pgrep -fl "^/usr/bin/dns-sd -P $ServiceName _$ApplicationLayer\._$TransportLayer $DomainName $PortNumber $HostName $IpAddress$" >/dev/null 2>&1; then
		LOG_SUCCESS "dns-sd is running with: $ServiceName _$ApplicationLayer._$TransportLayer $DomainName $PortNumber $HostName $IpAddress"
		exit "${EXIT_OK}"
	fi

	pgrepStdOut=$(pgrep -fl "^/usr/bin/dns-sd -P .+ $HostName $IpAddress$" 2>/tmp/pgrep.$$.stderr) || pgrepExit=$?
	pgrepStdErr=$(cat /tmp/pgrep.$$.stderr; rm -f /tmp/pgrep.$$.stderr)

	LOG_DEBUG "pgrep Status Code: $pgrepExit"
	LOG_DEBUG "pgrep StdOut Stream: $pgrepStdOut"
	LOG_DEBUG "pgrep StdErr Stream: $pgrepStdErr"

	if [[ -n "$pgrepStdErr" ]]; then
		LOG_ERROR "pgrep error: $pgrepStdErr"
		exit "${EXIT_ENV_ERROR}"
	elif [[ "$pgrepExit" -eq 0 && -n "$pgrepStdOut" ]]; then
		LOG_WARN "dns-sd is running, however configuration maybe abnormal see: $pgrepStdOut"
		exit "${EXIT_DNS_ABNORMAL_CONFIG}"
	elif [[ "$pgrepExit" -eq 1 ]]; then
		LOG_WARN "dns-sd process not found for $HostName. Checking /etc/hosts file for entry."
		check_etc_hosts "$IpAddress" "$HostName"
	else
		LOG_ERROR "pgrep exited with unexpected code: $pgrepExit"
		exit "${EXIT_ENV_ERROR}" 
	fi
fi