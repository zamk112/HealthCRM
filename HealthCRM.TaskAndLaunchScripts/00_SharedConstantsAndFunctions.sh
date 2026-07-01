#!/bin/bash
# shellcheck disable=SC2034
COLOUR_OFF="\033[0m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
BLUE="\033[0;34m"
BOLD_RED="\033[1;31m"
BOLD_YELLOW="\033[1;33m"
BOLD_GREEN="\033[1;32m"
UNDERLINE_YELLOW="\033[4;33m"
UNDERLINE_GREEN="\033[4;32m"

readonly EXIT_OK=0
readonly EXIT_ENV_ERROR=1
readonly EXIT_CERT_INVALID=10
readonly EXIT_MISSING_DNS_ENTRY=11
readonly EXIT_DNS_ABNORMAL_CONFIG=12
readonly EXIT_USAGE_ERROR=64

readonly OPENSSL_REQUIRED_MIN_VERSION=(3 0 13)
KERNEL=$(uname -s | tr "[:upper:]" "[:lower:]")

readonly LOG_LEVEL_ERROR=0
readonly LOG_LEVEL_WARN=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_VERBOSE=3
readonly LOG_LEVEL_DEBUG=4

LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

CHECK_OPEN_SSL_VERSION()
{
    if command -v openssl >/dev/null 2>&1; then
        
        versionNumbers=$(sed -nE 's/^OpenSSL ([[:digit:]]+)\.([[:digit:]]+)\.([[:digit:]]+) .+$/\1 \2 \3/p' <<< "$(openssl version)")

        if [[ -z "${versionNumbers}" ]]; then
            echo -e "${BOLD_RED}OpenSSL not detected (LibreSSL or unknown SSL implementation found).${COLOUR_OFF}" >&2
            exit "${EXIT_ENV_ERROR}"
        fi

        read -ra actualVersion <<< "${versionNumbers}"

        isTooOld=false

        for ((i=0; i<${#OPENSSL_REQUIRED_MIN_VERSION[@]}; i++)); do
            if ((actualVersion[i] < OPENSSL_REQUIRED_MIN_VERSION[i])); then
                isTooOld=true
                break
            fi
            if ((actualVersion[i] > OPENSSL_REQUIRED_MIN_VERSION[i])); then
                break
            fi
        done

        if $isTooOld; then
            echo -e "${BOLD_RED}OpenSSL must be ${OPENSSL_REQUIRED_MIN_VERSION[0]}.${OPENSSL_REQUIRED_MIN_VERSION[1]}.${OPENSSL_REQUIRED_MIN_VERSION[2]} or greater.${COLOUR_OFF}" >&2
            exit "${EXIT_ENV_ERROR}"
        fi

    else
        echo -e "${BOLD_RED}Require OpenSSL version ${OPENSSL_REQUIRED_MIN_VERSION[0]}.${OPENSSL_REQUIRED_MIN_VERSION[1]}.${OPENSSL_REQUIRED_MIN_VERSION[2]} or greater to be installed.${COLOUR_OFF}" >&2
        exit "${EXIT_ENV_ERROR}"
    fi
}

LOG_ERROR() {
    echo -e "${BOLD_RED}[$(date '+%H:%M:%S')][ERROR]   $*${COLOUR_OFF}" >&2
}

LOG_WARN() {
    (( LOG_LEVEL >= LOG_LEVEL_WARN )) || return 0
    echo -e "${YELLOW}[$(date '+%H:%M:%S')][WARN]    $*${COLOUR_OFF}" >&2
}

LOG_INFO() {
    (( LOG_LEVEL >= LOG_LEVEL_INFO )) || return 0
    echo -e "[$(date '+%H:%M:%S')][INFO]    $*" >&2
}

LOG_STEP() {
    (( LOG_LEVEL >= LOG_LEVEL_INFO )) || return 0
    echo -e "${BOLD_YELLOW}[$(date '+%H:%M:%S')][STEP]${COLOUR_OFF}    ${BOLD_YELLOW}$*${COLOUR_OFF}" >&2
}

LOG_VERBOSE() {
    (( LOG_LEVEL >= LOG_LEVEL_VERBOSE )) || return 0
    echo -e "${CYAN}[$(date '+%H:%M:%S')][VERBOSE] $*${COLOUR_OFF}" >&2    
}

LOG_DEBUG() {
    (( LOG_LEVEL >= LOG_LEVEL_DEBUG )) || return 0
    echo -e "${PURPLE}[$(date '+%H:%M:%S')][DEBUG]   $*${COLOUR_OFF}" >&2    
}

LOG_SUCCESS() {
    (( LOG_LEVEL >= LOG_LEVEL_INFO )) || return 0
    echo -e "${BOLD_GREEN}[$(date '+%H:%M:%S')][OK]${COLOUR_OFF}      ${BOLD_GREEN}$*${COLOUR_OFF}" >&2
}