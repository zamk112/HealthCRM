#!/bin/bash
set -euo pipefail

usage() {
	echo "usage: $(basename "$0") [-a <application name>][-d <dns name>][-i <ip address>][-n <application name>][-p <port number>][-t <transmission protocol>][-v|-vv][-h]"
}

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ScriptDir/00_SharedConstantsAndFunctions.sh"

HostName=""
DomainName=""
ApplicationLayer=""
ApplicationName=""
TransportLayer=""
PortNumber=""
IpAddress=""

while getopts "a:o:d:i:n:p:t:hv" opt; do
	case "$opt" in
		a) ApplicationLayer="${OPTARG// /}" ;;
		o) HostName="${OPTARG// /}" ;;
		d) DomainName=${OPTARG// /} ;;
		i) IpAddress="${OPTARG// /}" ;;
		n) ApplicationName="${OPTARG}" ;;
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

if [[ "$KERNEL" == "darwin" ]] && pgrep -fl "^/usr/bin/dns-sd -P $ApplicationName _$ApplicationLayer\._$TransportLayer $DomainName $PortNumber $HostName $IpAddress$" >/dev/null 2>&1; then
	LOG_SUCCESS "dns-sd is running $ApplicationName"
	exit "${EXIT_OK}"
else
	if grep -E "^${IpAddress}[[:space:]]+$HostName$" "/etc/hosts" >/dev/null 2>&1; then
		LOG_SUCCESS "DNS entry in /etc/hosts file detected."
		exit "${EXIT_OK}"
	else
		LOG_WARN "DNS entry for $HostName is not bound to any particular service."
		exit "${EXIT_MISSING_DNS_ENTRY}"
	fi
fi 
