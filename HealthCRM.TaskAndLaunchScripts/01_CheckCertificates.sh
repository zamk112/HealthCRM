#!/bin/bash
set -euo pipefail

usage() {
    echo "usage: $(basename "$0") [-f <name>[,<name>...]]... [-v|-vv][-h]"
}

parse_cert_expiry_date() {
    local expiryDate=$1
    case "$KERNEL" in
        darwin)
            date -j -f "%b %e %H:%M:%S %Y %Z" "$expiryDate" "+%s" 2>/dev/null
            ;;
        linux)
            date -d "$expiryDate" "+%s" 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ScriptDir/00_SharedConstantsAndFunctions.sh"

CertFullPathNames=()

while getopts ":f:hv" opt; do
    case "$opt" in 
        f) cleaned="${OPTARG// /}"
           IFS=',' read -ra newNames <<< "$cleaned"
           CertFullPathNames+=("${newNames[@]}") ;;
        h) usage ; exit "$EXIT_OK" ;;
        v) ((LOG_LEVEL++)) ;;
        \?) echo "Unknown Flag: -$OPTARG" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;
        :) echo "Flag -$OPTARG Requires A Value" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;
    esac
done
shift $((OPTIND - 1))

LOG_STEP "Checking If Certificate Paths Has Been Provided."
if (( ${#CertFullPathNames[@]} == 0 )); then
    LOG_ERROR "Certificate Paths Are Not Provided."
    exit "$EXIT_ENV_ERROR"
fi
LOG_SUCCESS "Certificate Paths Are Provided."

LOG_STEP "Validating OpenSSL Version."
CHECK_OPEN_SSL_VERSION
LOG_SUCCESS "OpenSSL Version Validated."

LOG_STEP "Validating Certificate Expiry."
for cert in "${CertFullPathNames[@]}"; do
    LOG_VERBOSE "Checking Certificate File: $cert"
    LOG_DEBUG "Reading And Extracting Out Certificate Expiry Date From '${cert##*/}'"
    if ! expiryDate=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2); then
        LOG_ERROR "Couldn't Read Certificate: ${cert##*/}"
        exit "$EXIT_CERT_INVALID"                
    fi
    LOG_DEBUG "Reading And Extracting Out Certificate Expiry Date From '${cert##*/}' Is Completed."

    LOG_DEBUG "Parsing Expiry Date From '${cert##*/}' On '$KERNEL'"
    if ! expiryTimestamp=$(parse_cert_expiry_date "$expiryDate"); then
        LOG_ERROR "Couldn't parse expiry date: $expiryDate"
        exit "$EXIT_CERT_INVALID"
    fi
    LOG_DEBUG "Parsing Expiry Date From '${cert##*/}' On '$KERNEL' Completed."

    LOG_DEBUG "Checking If Certificate '${cert##*/}' Is or Is Not Expired."
    currentTimestamp=$(date +%s)

    if ((currentTimestamp > expiryTimestamp)); then
        LOG_WARN "Certificate ${cert##*/} Is Expired"
        exit "$EXIT_CERT_INVALID"
    else
        daysLeft=$(( (expiryTimestamp - currentTimestamp) / 86400 ))
        LOG_INFO "Certificate ${cert##*/} Is Valid.\n\t\t    ${BLUE}Days Remaining: $daysLeft${COLOUR_OFF}"
    fi
    LOG_DEBUG "Certificate '${cert##*/}' Expiry Check Completed."
done

LOG_SUCCESS "Certificate Expiry Validated."

exit "$EXIT_OK"

