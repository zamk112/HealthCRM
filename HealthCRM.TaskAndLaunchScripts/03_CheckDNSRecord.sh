#!/bin/bash
set -euo pipefail

usage() {
	echo "usage: $(basename "$0") [-a <application name>][-d <dns name>][-e <standard out path>][-f <standard error path>][-i <ip address>][-l <label>][-o <hostname>][-n <application name>][-p <port number>][-s <service name>][-t <transmission protocol>][-k][-r][-v|-vv][-h]"
}

check_etc_hosts()
{
	local ipAddress=${1:?check_etc_hosts: IP Address is missing at position 1.}
	local hostName=${2:?check_etc_hosts: Hostname is missing at position 2.}
	if grep -E "^${ipAddress}[[:space:]]+$hostName$" "$ETC_HOSTS_PATH" >/dev/null 2>&1; then
		LOG_SUCCESS "DNS entry in /etc/hosts file detected."
		exit "$EXIT_OK_NO_CONFIG_CHANGE"
	else
		LOG_WARN "DNS entry for $hostName is not bound to any particular service."
		exit "$EXIT_MISSING_DNS_ENTRY"
	fi
}

check_plist_args()
{
	: "${1:?check_plist_args: needle value is missing from position 1.}"
	: "${2?check_plist_args: plistArray value is missing from position 2.}"
	local needle=$1
	shift
	local plistArray=("$@")

	local item
	for item in "${plistArray[@]}"; do 
		LOG_DEBUG "Comparing needle: '$needle' with item: '$item'"
		[[ "$item" == "$needle" ]] && return 0
	done

	return 1
}

pgrep_zero_dns_conf_check()
{
	local ipAddress=${1:?pgrep_zero_dns_conf_check: IP Address is missing at position 1.}
	local hostName=${2:?pgrep_zero_dns_conf_check: Hostname is missing at position 2.}
	local serviceName=${3:-}
	local type=${4:-}
	local domainName=${5:-}
	local portNumber=${6:-}

	local pgrepExit=0
	local pgrepStdOut=""
	local pgrepStdErr=""

	LOG_DEBUG "IP Address: '$ipAddress'"
	LOG_DEBUG "Host Name: '$hostName'"
	LOG_DEBUG "Service Name: '$serviceName'"
	LOG_DEBUG "Type: '$type'"
	LOG_DEBUG "Domain Name: '$domainName'"
	LOG_DEBUG "Port Number: '$portNumber'"

	if [[ -n $serviceName && -n $type && -n $domainName && -n $portNumber ]]; then
		LOG_VERBOSE "Executing pgrep to check if dns-sd service is running with all parameters provided."
		pgrepStdOut=$(pgrep -fl "^/usr/bin/dns-sd -P $serviceName $type $domainName $portNumber $hostName $ipAddress$" 2>/tmp/pgrep.$$.stderr) || pgrepExit=$?
	else
		LOG_VERBOSE "Executing pgrep to check if dns-sd service is running with IP address and hostname."
		pgrepStdOut=$(pgrep -fl "^/usr/bin/dns-sd -P .+ $hostName $ipAddress$" 2>/tmp/pgrep.$$.stderr) || pgrepExit=$?
	fi

	pgrepStdErr=$(cat /tmp/pgrep.$$.stderr; rm -f /tmp/pgrep.$$.stderr)

	LOG_DEBUG "pgrep Status Code: $pgrepExit"
	LOG_DEBUG "pgrep StdOut Stream: $pgrepStdOut"
	LOG_DEBUG "pgrep StdErr Stream: $pgrepStdErr"	
	
	printf '%s;%s;%s' "$pgrepExit" "$pgrepStdOut" "$pgrepStdErr"
}

check_dns_sd_service_is_running()
{
	local ipAddress=${1:?check_dns_sd_service_is_running: IP Address is missing at position 1.}
	local hostName=${2:?check_dns_sd_service_is_running: Hostname is missing at position 2.}
	local serviceName=${3:-}
	local type=${4:-}
	local domainName=${5:-}
	local portNumber=${6:-}

	local pgrepExit=0
	local pgrepStdOut=""
	local pgrepStdErr=""

	LOG_DEBUG "IP Address: '$ipAddress'"
	LOG_DEBUG "Host Name: '$hostName'"
	LOG_DEBUG "Service Name: '$serviceName'"
	LOG_DEBUG "Type: '$type'"
	LOG_DEBUG "Domain Name: '$domainName'"
	LOG_DEBUG "Port Number: '$portNumber'"

	if [[ -n $serviceName && -n $type && -n $domainName && -n $portNumber ]]; then
		LOG_VERBOSE "Reading in and storing pgrep output with all parameters provided."
		IFS=';' read -rd '' pgrepExit pgrepStdOut pgrepStdErr < <(pgrep_zero_dns_conf_check "$ipAddress" "$hostName" "$serviceName" "$type" "$domainName" "$portNumber") || true
	else
		LOG_VERBOSE "Reading in and storing pgrep output with only IP Address and Host Name."
		IFS=';' read -rd '' pgrepExit pgrepStdOut pgrepStdErr < <(pgrep_zero_dns_conf_check "$ipAddress" "$hostName") || true
	fi

	LOG_VERBOSE "Checking pgrep outputs."
	if [[ -n "$pgrepStdErr" ]]; then
		LOG_ERROR "pgrep error: $pgrepStdErr"
		exit "$EXIT_ENV_ERROR"
	elif [[ "$pgrepExit" -eq 0 && -n "$pgrepStdOut" ]]; then
		LOG_SUCCESS "dns-sd service is running: See output: '$pgrepStdOut'."
		return 0
	elif [[ "$pgrepExit" -eq 1 ]]; then
		if [[ -n $serviceName && -n $type && -n $domainName && -n $portNumber ]]; then
			LOG_WARN "Unable to find by Service Name: '$serviceName', Type: '$type', Domain Name: '$domainName' and by Port Number: '$portNumber'. Checking with only IP Address and Host."
			IFS=';' read -rd '' pgrepExit pgrepStdOut pgrepStdErr < <(pgrep_zero_dns_conf_check "$ipAddress" "$hostName") || true
			if [[ "$pgrepExit" -eq 0 && -n "$pgrepStdOut" ]]; then
				LOG_WARN "dns-sd process is running, but under different configuration, see: '$pgrepStdOut'"
			else 
				LOG_WARN "dns-sd process was not found for $hostName."
			fi
		else
			LOG_WARN "dns-sd process was not found for $hostName."
		fi
		return 1
	else
		LOG_ERROR "pgrep exited with unexpected code: $pgrepExit"
		exit "$EXIT_ENV_ERROR" 
	fi
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

configMalformed=false

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

LOG_STEP "Checking DNS Record On '$KERNEL'."
if [[ "$KERNEL" == "darwin" ]]; then 
	LOG_VERBOSE "Checking if a config already exists in '$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist'."
	if [[ -f "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist" ]]; then
		matchesOldConfig=true
		LOG_STEP "Comparing input with current '$Label.plist'."
		
		LOG_VERBOSE "Extracting plist data and exporting into xml format."
		plistXmlOutput=$(plutil -convert xml1 -o - "$LAUNCH_DAEMONS_DIRECTORY_PATH/$Label.plist")
		LOG_DEBUG "plist XML Output:\n$plistXmlOutput"

		LOG_VERBOSE "Extracting Label value from plist XML output."
		label=$(echo "$plistXmlOutput" | xmllint --xpath 'string(/plist/dict/key[text()="Label"]/following-sibling::*[1])' -)
		LOG_DEBUG "Config Label value: '$label'"
		
		LOG_VERBOSE "Checking if config Label is empty."
		if [[ -n "$label" ]]; then
			LOG_VERBOSE "Comparing input label with existing label config."
			if [[ "$label" == "$Label" ]]; then
				LOG_SUCCESS "Input Label '$Label' is a exact match as in the current config file."
			else
				LOG_WARN "Input Label '$Label' does not match '$label'."
				matchesOldConfig=false
			fi
		else
			LOG_WARN "Config Label does not exist in existing config."
		fi
		LOG_INFO "Checking Label values complete."

		LOG_VERBOSE "Extracting Keep Alive value from plist XML output."
		keepAlive=$(echo "$plistXmlOutput" | xmllint --xpath 'name(/plist/dict/key[text()="KeepAlive"]/following-sibling::*[1])' -)
		LOG_DEBUG "Config Keep Alive value: '$keepAlive'"

		LOG_VERBOSE "Checking if config Keep Alive value is not empty."
		if [[ -n "$keepAlive" ]]; then
			LOG_VERBOSE "Comparing Input Keep Alive value with current config Keep Alive value."
			if [[ "$keepAlive" == "$KeepAlive" ]]; then
				LOG_SUCCESS "Input Keep Alive Value: '$KeepAlive' matches current config file value."
			else
				LOG_WARN "Input Keep Alive Value: '$KeepAlive' does not match current config file value '$keepAlive'."
				matchesOldConfig=false
			fi
		else
			LOG_WARN "Using defaulted value of Keep Alive: '$KeepAlive'."
		fi
		LOG_INFO "Checking Keep Alive value complete."

		LOG_VERBOSE "Extracting Run At Load value from plist XML output."
		runAtLoad=$(echo "$plistXmlOutput" | xmllint --xpath 'name(/plist/dict/key[text()="RunAtLoad"]/following-sibling::*[1])' -)
		LOG_DEBUG "Config Run At Load Value: '$runAtLoad'."

		LOG_VERBOSE "Checking if the config Run At Load Value is not empty."
		if [[ -n "$runAtLoad" ]]; then
				LOG_VERBOSE "Comparing Input Run At Load value with current config Run At Load value."
			if [[ "$runAtLoad" == "$RunAtLoad" ]]; then
				LOG_SUCCESS "Input Run At Load value: '$runAtLoad' matches current config file."
			else
				LOG_WARN "Input Run At Load '$RunAtLoad' does not match current config file value '$runAtLoad'."
				matchesOldConfig=false
			fi
		else
			LOG_WARN "Using defaulted value of Run At Load: '$RunAtLoad'."
		fi
		LOG_INFO "Checking Run At Load value completed."

		LOG_VERBOSE "Extracting Standard Out Path value from plist XML output."
		standardOutPath=$(echo "$plistXmlOutput" | xmllint --xpath 'string(/plist/dict/key[text()="StandardOutPath"]/following-sibling::*[1])' -)
		LOG_DEBUG "Config Standard Out Path value: '$standardOutPath'."

		LOG_VERBOSE "Checking if config Standard Out Path value is not empty."
		if [[ -n "$standardOutPath" ]]; then
			LOG_VERBOSE "Check if config Standard Out Path is a valid directory."
			if [[ ! -d "${standardOutPath%/*}" ]]; then
				LOG_WARN "Current Config Standard Out Path is invalid or does not exist."
			else
				LOG_VERBOSE "Comparing input Standard Out Path with config Standard Out Path."
				if [[ "$StandardOutPath" == "${standardOutPath%/*}" ]]; then
					LOG_SUCCESS "Input Standard Out Path matches current config Standard Out Path."
				else
					LOG_VERBOSE "Only check if the input Standard Out Path is provided. Further Checking of input Standard Output Path will be done later."
					if [[ -n "$StandardOutPath" ]]; then
						LOG_WARN "Input Standard Out Path '$StandardOutPath' does not match the current config path '${standardOutPath%/*}'."
					fi
					matchesOldConfig=false
				fi	
			fi
		else
			LOG_WARN "Unable to retrieve Config Standard Out Path from current config file."
		fi
		LOG_INFO "Checking Standard Out Path value completed."

		LOG_VERBOSE "Extracting Standard Error Path value from plist XML output."
		standardErrorPath=$(echo "$plistXmlOutput" | xmllint --xpath 'string(/plist/dict/key[text()="StandardErrorPath"]/following-sibling::*[1])' -)
		LOG_DEBUG "Config Standard Error Path value: '$standardErrorPath'"

		LOG_VERBOSE "Checking if config Standard Error Path is not empty."
		if [[ -n "$standardErrorPath" ]]; then
			LOG_VERBOSE "Checking if config Standard Error Path is a valid directory."
			if [[ ! -d "${standardErrorPath%/*}" ]]; then
				LOG_WARN "Current Config Standard Error Path is invalid or does not exist." 
			else
				LOG_VERBOSE "Comparing input Standard Error Path with config Standard Error Path."
				if [[ "$StandardErrorPath" == "${standardErrorPath%/*}" ]]; then
					LOG_SUCCESS "Input Standard Error Path matches current config Standard Error Path."
				else 
					LOG_VERBOSE "Only check if the input Standard Error Path is provided. Further Checking of input Standard Error Path will be done later."
					if [[ -n "$StandardErrorPath" ]]; then
						LOG_WARN "Input Standard Error Path '$StandardErrorPath' does not match the current config path '${standardErrorPath%/*}'."
					fi
					matchesOldConfig=false
				fi 
			fi
		else
			LOG_WARN "Unable to retrieve Config Standard Error Path from current config file."
		fi
		LOG_INFO "Checking Standard Error Path value completed."

		LOG_VERBOSE "Checking Config Program Arguments Array"
		configProgramArgumentsArr=()
		while read -r line; do 
			configProgramArgumentsArr+=("$line")
		done < <(echo "$plistXmlOutput" | xmllint --xpath '/plist/dict/key[text()="ProgramArguments"]/following-sibling::array[1]/string/text()' -)
		LOG_DEBUG "Reading in Config Program Arguments values:\n $(printf '\t\t\t* %s\n' "${configProgramArgumentsArr[@]}")"

		LOG_VERBOSE "Checking if program arguments is empty or not."
		if [[ -z "${configProgramArgumentsArr[*]}" ]]; then
			LOG_WARN "No Program Arguments Provided." 
		else
			LOG_VERBOSE "Constructing Argument Array from Input Values." 
			inputProgramArgumentsArr=(
				"$ServiceName"
				"_${ApplicationLayer}._${TransportLayer}"
				"$DomainName"
				"$PortNumber"
				"$HostName"
				"$IpAddress"
			)
			LOG_DEBUG "Input Argument Array values:\n$(printf '\t\t\t* %s\n' "${inputProgramArgumentsArr[@]}")"

			allFound=true

			LOG_VERBOSE "Comparing Input Program Arguments with Config Program Arguments."
			for expected in "${inputProgramArgumentsArr[@]}"; do
				if ! check_plist_args "$expected" "${configProgramArgumentsArr[@]}"; then
					allFound=false
					break
				fi
			done
			
			if $allFound; then
				LOG_SUCCESS "Program argument config is an exact match."
			else
				LOG_WARN "Program argument may be malformed." 
				LOG_VERBOSE "Retrieving Config Program Arguments excluding dns-sd bin path and proxy advertisement flag for comparison with Input Program Arguments."
				filteredConfigProgramArgumentsArr=()
				for arg in "${configProgramArgumentsArr[@]}"; do
					[[ "$arg" =~ \/usr\/bin\/dns-sd|-P ]] && continue
					filteredConfigProgramArgumentsArr+=("$arg")
				done
				LOG_DEBUG "Filtered Config Program Arguments:\n$(printf '\t\t\t* %s\n' "${filteredConfigProgramArgumentsArr[@]}")"

				sortedFilteredConfigProgramArgsArrStr=$(printf '%s\n' "${filteredConfigProgramArgumentsArr[@]}" | sort)
				LOG_DEBUG "Sorted Filtered Config Program Arguments:\n$(printf '\t\t\t* %s\n' "${filteredConfigProgramArgumentsArr[@]}" | sort)"
				sortedInputProgramArgsArrStr=$(printf '%s\n' "${inputProgramArgumentsArr[@]}" | sort)
				LOG_DEBUG "Sorted Input Arguments:\n$(printf '\t\t\t* %s\n' "${inputProgramArgumentsArr[@]}" | sort)"
				LOG_WARN "Difference between Current and Input Program Arguments:\n$(diff -u <(printf '%s\n' "${sortedFilteredConfigProgramArgsArrStr[@]}") <(printf '%s\n' "${sortedInputProgramArgsArrStr[@]}"))"
				matchesOldConfig=false
			fi
			LOG_INFO "Checking Program Arguments from Input to Config completed."

			LOG_VERBOSE "Checking Config Program Argument contains dns-sd bin path."
			if [[ ! "${configProgramArgumentsArr[*]}" =~ \/usr\/bin\/dns-sd ]]; then
				LOG_WARN "dns-sd path is missing or invalid in current config file."
				matchesOldConfig=false
			fi
			LOG_INFO "Config Program Argument contains dns-sd bin path is completed."

			LOG_VERBOSE "Checking Program Argument contains the proxy advertisement flag."
			if [[ ! "${configProgramArgumentsArr[*]}" =~ -P ]]; then
				LOG_WARN "Proxy advertisement flag is missing or current flag is invalid in current config file."
				matchesOldConfig=false
			fi
			LOG_INFO "Checking Program Argument contains the proxy advertisement flag is completed."

			LOG_VERBOSE "Checking if 'matchesOldConfig' is true'"
			LOG_DEBUG "Matches Old Config Flag Value: $matchesOldConfig"
			if [ "$matchesOldConfig" = true ]; then
				LOG_SUCCESS "Input config matches current config."
				LOG_STEP "Checking if dns-sd Service is running."
				check_dns_sd_service_is_running "$IpAddress" "$HostName" "$ServiceName" "_${ApplicationLayer}._${TransportLayer}" "$DomainName" "$PortNumber"
				exit "$EXIT_OK_NO_CONFIG_CHANGE"
			fi
			LOG_INFO "'matchesOldConfig' config is completed."
		fi
	fi
	LOG_VERBOSE "Checking if all required input has been passed or will check /etc/hosts file for config."
	if [[ -n "$Label" && -n "$HostName" && -n "$DomainName" && -n "$ServiceName" && -n "$ApplicationLayer" && -n "$TransportLayer" && -n "$PortNumber" && -n "$IpAddress" && -n "$RunAtLoad" && -n "$KeepAlive" && -n "$StandardOutPath" && -n "$StandardErrorPath" ]]; then
		LOG_VERBOSE "Checking if the Standard Out Path exists."
		if [[ -d "$StandardOutPath" ]]; then
			LOG_SUCCESS "Input Standard Out Path exists."

			LOG_VERBOSE "Checking if the Standard Out Path with same file name exists."
			if [[ -f "$StandardOutPath/${Label//./-}.log" ]]; then
				LOG_SUCCESS "Log File '${Label//./-}.log' exists in '$StandardOutPath'. When Service is running, output will be appended to file."
			else
				LOG_WARN "Log File '${Label//./-}.log' does not exists in '$StandardOutPath'. A new log file will be created when the service is running."
			fi
		else
			LOG_WARN "Input Standard Out Path does not exist or not provided."
			configMalformed=true
		fi
		LOG_INFO "Checking Standard Out Path file exists is completed."

		LOG_VERBOSE "Checking if the Standard Error Path with same file name exists."
		if [[ -d "$StandardErrorPath" ]]; then
			LOG_SUCCESS "Input Standard Error Path exists."

			LOG_VERBOSE "Checking if the Standard Error Path with same file name exists."			
			if [[ -f "$StandardErrorPath/${Label//./-}-error.log" ]]; then
				LOG_SUCCESS "Log File '${Label//./-}-error.log' exists in '$StandardErrorPath'. When Service is running, output will be appended to file."
			else
				LOG_WARN "Log File '${Label//./-}-error.log' does not exists in '$StandardErrorPath'. A new log file will be created when the service is running."
			fi
		else
			LOG_WARN "Input Standard Error Path does not exist or not provided."
			configMalformed=true
		fi
		LOG_INFO "Checking Standard Out Path file exists is completed."

		LOG_VERBOSE "Extracting Domain Name from Hostname and comparing with Input Domain Name"
		if [[ "${HostName##*.}" == "$DomainName" ]]; then
			LOG_SUCCESS "Input hostname domain matches input domain name."
		else
			LOG_WARN "Input hostname domain: '${HostName##*.}' does not match '$DomainName'."
			configMalformed=true
		fi
		LOG_INFO "Domain Name from Hostname comparison with Input Domain Name is completed."

		LOG_VERBOSE "Checking Input Transport Layer"
		if [[ "$TransportLayer" == "tcp" ]]; then
			LOG_SUCCESS "Input transport layer is using the correct protocol, which is TCP."
		else
			LOG_WARN "Input transport layer: '$TransportLayer' is not the correct protocol, which is TCP."
			configMalformed=true
		fi
		LOG_INFO "Checking Input Transport Layer is completed."

		LOG_VERBOSE "Checking Input Application Layer."
		if [[ "$ApplicationLayer" =~ ^http[s]?$ ]]; then
			LOG_SUCCESS "Input Application Layer protocol: '$ApplicationLayer' is the correct protocol."
		else
			LOG_WARN "Input Application Layer protocol: '$ApplicationLayer' is not the correct protocol."
			configMalformed=true
		fi
		LOG_INFO "Checking Input Application Layer check is completed."

		LOG_VERBOSE "Checking input Port Number is within valid range."
		if (( PortNumber >= 0 && PortNumber <= 65535 )); then
			LOG_SUCCESS "Input Port Number: '$PortNumber' is within the valid range."

			if [[ "$ApplicationLayer" == "http" ]] && (( PortNumber == 80 || PortNumber == 8080 )); then
				LOG_SUCCESS "http protocol is using the correct port number which is '$PortNumber'".
			elif [[ "$ApplicationLayer" == "https" ]] && (( PortNumber == 443 )); then
				LOG_SUCCESS "https protocol is using the correct port number which is '$PortNumber'".
			fi
		else
			LOG_WARN "Port Number: '$PortNumber' is not within valid range."
			configMalformed=true
		fi
		LOG_INFO "Validation of input Port Number check is completed."

		if [ $configMalformed = false ]; then
			LOG_VERBOSE "If config is not malformed, check if there's a dns-sd service running."
			check_dns_sd_service_is_running "$IpAddress" "$HostName"
		fi
	else
		LOG_STEP "Checking and reporting missing input parameters for dns-sd service"
		missingConfigKeys=("Label" "Host Name" "Domain Name" "Service Name" "Application Name" "Transport Layer" "Port Number" "IP Address" "Run At Load" "Keep Alive" "Standard Out Path" "Standard Error Path")
		missingConfigValues=("$Label" "$HostName" "$DomainName" "$ServiceName" "$ApplicationLayer" "$TransportLayer" "$PortNumber" "$IpAddress" "$RunAtLoad" "$KeepAlive" "$StandardOutPath" "$StandardErrorPath")
		missing=()

		LOG_VERBOSE "Checking for missing input parameters."
		for ((i=0; i<${#missingConfigValues[@]}; i++)); do
			if [[ -z "${missingConfigValues[$i]}" ]]; then
				missing+=("${missingConfigKeys[$i]}")
			fi
		done
		LOG_DEBUG "Missing Input Parameters:\n$(printf '\t\t\t* %s\n' "${missing[@]}")"

		missingCount=${#missing[@]}
		LOG_DEBUG "Missing Count value: '$missingCount'"
		missingMessage="The following config values are missing: "

		for ((i=0; i<missingCount; i++)); do
			if [ "$missingCount" -eq 1 ]; then
				missingMessage+="'${missing[$i]}'"
			elif [ $i -eq $((missingCount - 1)) ]; then
				missingMessage+="and '${missing[$i]}'"
			elif [ $i -eq $((missingCount - 2)) ]; then
				missingMessage+="'${missing[$i]}' "
			else
				missingMessage+="'${missing[$i]}', "
			fi
		done

		LOG_WARN "${missingMessage}."
		LOG_STEP "Checking /etc/hosts config file for DNS entry."
		check_etc_hosts "$IpAddress" "$HostName"
	fi
fi

if [ "$configMalformed" = true ]; then
	exit "$EXIT_DNS_ABNORMAL_CONFIG"
else
	exit "$EXIT_OK_CONFIG_CHANGE"
fi