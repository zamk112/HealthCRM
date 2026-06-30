#!/bin/bash
set -euo pipefail
trap 'unset Password CA_KEY_PASSWORD 2>/dev/null; \
      echo -e "${BOLD_RED}Generation failed at line $LINENO${COLOUR_OFF}" >&2' ERR
trap 'unset Password CA_KEY_PASSWORD 2>/dev/null' EXIT

usage() {
    echo "usage: $(basename "$0") [-c <config>[,<config>...]]... [-f <cert>[,<cert>...]]... [-r][-v|-vv][-h]"
}

config_has_section() {
    local configFile=$1
    local sectionName=$2
    grep -qE "^\[[[:space:]]*${sectionName}[[:space:]]*\]" "$configFile"
}

delete_certificate_files()
{
    local file
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            rm "$file"
            LOG_INFO "Removed File: '${file##*/}'"
        fi
    done
}

ScriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ScriptDir/00_SharedConstantsAndFunctions.sh"

ConfigFullPathNames=()
CertFullPathNames=()
FullReload=false

CaConfigPath="" 
CaCertPath=""
CaKeyPath=""
CaSrlPath=""
ServerConfigPath="" 
ServerCSRPath=""
ServerCertPath=""
ServerKeyPath=""
ServerPfxPath=""
ServerEnvPath=""
ClientConfigPath="" 
ClientCSRPath=""
ClientCertPath=""
ClientKeyPath=""

while getopts ":c:f:rhv" opt; do
    case "$opt" in 
        c) cleaned="${OPTARG// /}"
           IFS=',' read -ra newNames <<< "$cleaned"
           ConfigFullPathNames+=("${newNames[@]}") ;;
        f) cleaned="${OPTARG// /}"
           IFS=',' read -ra newNames <<< "$cleaned"
           CertFullPathNames+=("${newNames[@]}") ;;
        r) FullReload=true ;;
        h) usage ; exit "$EXIT_OK" ;;
        v) ((LOG_LEVEL++)) ;;
        \?) echo "Unknown Flag: -$OPTARG" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;
        :) echo "Flag -$OPTARG Requires A Value" >&2; usage >&2 ; exit "$EXIT_USAGE_ERROR" ;;        
    esac
done
shift $((OPTIND - 1))

CHECK_OPEN_SSL_VERSION

LOG_STEP "Checking If Certificate Config Paths Has Been Provided."
if (( ${#ConfigFullPathNames[@]} == 0 )); then
    LOG_ERROR "Config Path Are Not Provided."
    exit "$EXIT_USAGE_ERROR"
fi
LOG_SUCCESS "Certificate Config Paths Are Provided."

LOG_STEP "Validating Certificate Config Files."
for config in "${ConfigFullPathNames[@]}"; do
    LOG_VERBOSE "Checking Config File: '$config'"
    LOG_DEBUG "Checking Config File: '${config##*/}' To See If File Name contains CA, Server or Client"
    if [[ ! "$config" =~ .+\.(CA|Server|Client)\.cert\.conf$ ]]; then
        LOG_ERROR "Config '${config##*/}' Is Not Valid Or It Does Not Exist."
        LOG_ERROR "  (Expected: <name>.{CA,Server,Client}.cert.conf)"
        exit "$EXIT_ENV_ERROR"
    fi
    LOG_DEBUG "Config File: '${config##*/}' Does Contain Valid Name (CA, Server or Client)."

    LOG_DEBUG "Checking If Config File '${config##*/}' Exists."
    if [[ ! -f "$config" ]]; then
        LOG_ERROR "Config File: '${config##*/}' Not Found."
        exit "$EXIT_ENV_ERROR"
    fi
    LOG_DEBUG "Config File '${config##*/}' Exists."

    case "$config" in 
        *.CA.cert.conf) 
            CaConfigPath="$config" 
            LOG_VERBOSE "Checking If The 'CA' Certificate Config File Contains The Relevant Sections."
            for section in req req_distinguished_name v3_ca; do
                LOG_DEBUG "Checking If Section [$section] Exists In '${config##*/}'"
                if ! config_has_section "$config" "$section"; then
                    LOG_ERROR "CA Config File Is '${config##*/}' Missing [$section] Section."
                    exit "$EXIT_ENV_ERROR"
                fi
                LOG_DEBUG "Section [$section] Exists In '${config##*/}'"
            done
            LOG_VERBOSE "'CA' Certificate Config File Sections Contains Relevant Sections."
            ;;
        *.Server.cert.conf) 
           ServerConfigPath="$config"
           LOG_VERBOSE "Checking If The 'Server' Certificate Config File Contains The Relevant Sections." 
            for section in req req_distinguished_name v3_sign alt_names; do
                LOG_DEBUG "Checking If Section [$section] Exists In '${config##*/}'"
                if ! config_has_section "$config" "$section"; then
                    LOG_ERROR "'Server' Config File: '${config##*/}' Is Missing [$section] Section"
                    exit "$EXIT_ENV_ERROR"
                fi
                LOG_DEBUG "Section [$section] Exists In '${config##*/}'"
            done
            LOG_VERBOSE "'Server' Certificate Config File Sections Contains Relevant Sections."
            ;;
        *.Client.cert.conf) 
            ClientConfigPath="$config" 
            LOG_VERBOSE "Checking If The 'Client' Certificate Config File Contains The Relevant Sections." 
            for section in req req_distinguished_name v3_sign alt_names; do
                LOG_DEBUG "Checking If Section [$section] Exists In '${config##*/}'"
                if ! config_has_section "$config" "$section"; then
                    LOG_ERROR "'Client' Config File: '${config##*/}' Is Missing [$section] Section"
                    exit "$EXIT_ENV_ERROR"
                fi
                LOG_DEBUG "Section [$section] Exists In '${config##*/}'"
            done
            LOG_VERBOSE "'Client' Certificate Config File Sections Contains Relevant Sections."
            ;;
        *)
            LOG_ERROR "Unrecognized config: ${config##*/}"
            exit "$EXIT_USAGE_ERROR"
            ;;
    esac
    LOG_VERBOSE "Checks Completed On Config File: '$config'"
done
LOG_SUCCESS "Certificate Config Files Validation Completed."

LOG_STEP "Checking If Certificate Paths Has Been Provided."
if (( ${#CertFullPathNames[@]} == 0 )); then
    LOG_ERROR "Certificate Paths Are Not Provided."
    exit "$EXIT_USAGE_ERROR"
fi
LOG_SUCCESS "Certificate Paths Are Provided."

LOG_STEP "Validating Certificate File Paths."
for cert in "${CertFullPathNames[@]}"; do 
    LOG_VERBOSE "Checking Certificate Path: $cert"

    if [[ ! "$cert" =~ .+\.(CA|Server|Client)\.pem$ ]]; then
        LOG_ERROR "Config '${cert##*/}' Is Not Valid."
        LOG_ERROR "  (Expected: <name>.{CA,Server,Client}.pem)"
        exit "$EXIT_ENV_ERROR"        
    fi
    
    directoryPath=$(dirname "$cert")
    LOG_DEBUG "Checking Directory Path: '$directoryPath'; For Certificate: '${cert##*/}'"
    if [[ ! -d "$directoryPath" ]]; then
        LOG_ERROR "Directory: '$directoryPath' Does Not Exist."
        exit "$EXIT_ENV_ERROR"
    fi
    LOG_DEBUG "Directory Path: '$directoryPath'; For Certificate: '${cert##*/}' Check Is Completed."

    LOG_VERBOSE "Starting To Strip Out Extension From File '${cert##*/}' For Creation And Deletion of Certificate Relevant Files With Directory Paths."
    base="${cert%.pem}"
    case "$cert" in 
        *.CA.pem) CaCertPath="$cert" ; CaKeyPath="$base.key"; CaSrlPath="$base.srl" 
            LOG_DEBUG "CA Certificate Path: $CaCertPath"
	        LOG_DEBUG "CA Certificate Key Path: $CaKeyPath"
	        LOG_DEBUG "CA Certificate Serial Path: $CaSrlPath"
        ;;
        *.Server.pem) ServerCertPath="$cert"; ServerKeyPath="$base.key"; ServerCSRPath="$base.csr"; ServerPfxPath="$base.pfx"; ServerEnvPath="$base.env" 
            LOG_DEBUG "Server Certificate Path $ServerCertPath"
            LOG_DEBUG "Server Certificate Key Path: $ServerKeyPath"
            LOG_DEBUG "Server Certificate CSR Path: $ServerCSRPath"
            LOG_DEBUG "Server Certificate PFX Path: $ServerPfxPath"
            LOG_DEBUG "Server Certificate Environment Variable Path: $ServerEnvPath"
        ;;
        *.Client.pem) ClientCertPath="$cert"; ClientKeyPath="$base.key"; ClientCSRPath="$base.csr" 
            LOG_DEBUG "Client Certificate Path: $ClientCertPath"
            LOG_DEBUG "Client Certificate Key Path: $ClientKeyPath"
            LOG_DEBUG "Client Certificate CSR Path: $ClientCSRPath"
        ;;
        *)
            LOG_ERROR "Unrecognized certificate: '$cert'"
            exit "$EXIT_USAGE_ERROR"
        ;;
    esac
    LOG_VERBOSE "Stripping Out File Extension From File '${cert##*/}' For Creation and Deletion of Certificate Relevant Files With Directory Paths Completed."
    LOG_VERBOSE "Certificate Check For '$cert' Is Now Completed."
done
LOG_SUCCESS "Validation of Certificate File Paths Completed."

LOG_STEP "Validating Certificate And Config File Combinations"
RequiredPairs=(
    "CA:CaConfigPath:CaCertPath"
    "Server:ServerConfigPath:ServerCertPath"
    "Client:ClientConfigPath:ClientCertPath"
)

for pair in "${RequiredPairs[@]}"; do
    LOG_VERBOSE "Checking Pair '$pair'."
    IFS=':' read -r name configVar certVar <<< "$pair"

    if [[ -z "${!configVar}" ]]; then
        echo -e "${BOLD_RED}Missing config for $name${COLOUR_OFF}" >&2
        exit "$EXIT_USAGE_ERROR"
    fi

    if [[ -z "${!certVar}" ]]; then
        echo -e "${BOLD_RED}Missing certificate for $name${COLOUR_OFF}" >&2
        exit "$EXIT_USAGE_ERROR"
    fi
    LOG_VERBOSE "Pair '$pair' Completed."
done
LOG_SUCCESS "Validation of Certificate And Config File Combination Complete."

LOG_VERBOSE "Retrieving CN Value From CA Certificate Config File."
CaCommonName=$(sed -nE "s/^CN[[:space:]]*=[[:space:]]*[\"']?[[:space:]]*([^\"']+)[[:space:]]*[\"']?[[:space:]]*\$/\1/p" "$CaConfigPath")

if [[ -z "$CaCommonName" ]]; then
    echo -e "${BOLD_RED}Could not extract CN from $CaConfigPath${COLOUR_OFF}" >&2
    exit "$EXIT_ENV_ERROR"
fi

LOG_DEBUG "Removing Trailing And Leading Whitespaces From CN Name."
CaCommonName="${CaCommonName#"${CaCommonName%%[![:space:]]*}"}"
CaCommonName="${CaCommonName%"${CaCommonName##*[![:space:]]}"}"
LOG_VERBOSE "Common Name Retrieved From CA Certificate Config File Completed."

LOG_SUCCESS "Certificate Config & Certificate File Paths Check Completed..."

LOG_STEP "Deleting Old Certificate Files."
delete_certificate_files \
    "$CaCertPath" \
    "$ServerCertPath" \
    "$ServerPfxPath" \
    "$ServerEnvPath" \
    "$ClientCertPath" 

if [ "$FullReload" = true ]; then
    LOG_STEP "Deleting Certificate Key, CSR and CA SRL file(s)."
    delete_certificate_files \
        "$CaKeyPath" \
        "$CaSrlPath" \
        "$ServerCSRPath" \
        "$ServerKeyPath" \
        "$ClientCSRPath" \
        "$ClientKeyPath"
fi

if [[ "$KERNEL" == "darwin" ]] && security find-certificate -c "$CaCommonName" /Library/Keychains/System.keychain >/dev/null 2>&1; then
    LOG_DEBUG "Deleting CA Certificate '$CaCommonName' From The MacOS Certificate Store."
    sudo security delete-certificate -c "$CaCommonName" /Library/Keychains/System.keychain
    LOG_INFO "Deleted CA certificate '$CaCommonName' from MacOS certificate store."

elif [[ "$KERNEL" == "linux" ]]; then
    if certutil -L -d ~/.pki/nssdb -n "$CaCommonName" >/dev/null 2>&1; then
        LOG_DEBUG "Deleting CA Certificate '$CaCommonName' From Google Chrome NSSDB."
        certutil -D -d ~/.pki/nssdb -n "$CaCommonName"
        LOG_INFO "Deleted CA Certificate '$CaCommonName' From Google Chrome NSSDB."
    fi
else
    LOG_WARN "Please Make Sure To Delete The CA Certificate With the CN '$CaCommonName' From Your Relevant Certificate Store(s) on your OS/Application."
fi

LOG_SUCCESS "Certificate Deletion Completed."

LOG_STEP "Generating Certificates."
read -rsp "Enter Certificate password: " Password
echo

if [[ -f "$CaKeyPath" ]] && [ "$FullReload" = false ]; then 
    LOG_INFO "CA Certificate Private Already Exists. Skipping CA Private Key Generation."
else
    LOG_STEP "Generating RSA Private Key for CA Certificate With File Name: '${CaKeyPath##*/}'"
    CA_KEY_PASSWORD="$Password" openssl genrsa -aes256 -passout env:CA_KEY_PASSWORD -out "$CaKeyPath" 2048
    LOG_SUCCESS "RSA Private Key Generation With File Name '${CaKeyPath##*/}' Is Completed."
fi

LOG_STEP "Generating CA Certificate With File Name: '${CaKeyPath##*/}'."
CA_KEY_PASSWORD="$Password" openssl req -x509 -new \
  -key "$CaKeyPath" \
  -sha256 -days 365 \
  -config "$CaConfigPath" \
  -out "$CaCertPath" \
  -passin env:CA_KEY_PASSWORD
LOG_SUCCESS "CA Certificate With File Name: '${CaKeyPath##*/}' Generation Is Completed."

if [[ "$KERNEL" == "darwin" ]]; then
	LOG_STEP "Adding CA Certificate '${CaCertPath##*/}' To MacOS Certificate Store."
    sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    "$CaCertPath"
	LOG_SUCCESS "CA Certificate '${CaCertPath##*/}' Successfully Added To The MacOS Certificate Store."
elif [[ "$KERNEL" == "linux" ]]; then
    LOG_STEP "Adding CA Certificate '${CaCertPath##*/}' To The Google Chrome NSSDB."
    certutil -A \
    -d ~/.pki/nssdb \
    -n "$CaCommonName" \
    -t "CT,," \
    -i "$CaCertPath"
    LOG_SUCCESS "CA Certificate '${CaCertPath##*/}' Added To The Google Chrome NSSDB."
else
    LOG_WARN "Please Make Sure to Add Your CA Certificate '${CaCertPath##*/}' To The Relevant Certificate Store/Application."
fi

if [[ -f "$ServerKeyPath" ]] && [ "$FullReload" = false ]; then
    LOG_INFO "Server Private Key Already Exists. Skipping Server Private Key Generation."
else
    LOG_STEP "Generating Server Private Key '${ServerKeyPath##*/}' And CSR '${ServerCSRPath##*/}'."
    openssl req -new \
    -newkey rsa:2048 \
    -noenc \
    -keyout "$ServerKeyPath" \
    -config "$ServerConfigPath" \
    -out "$ServerCSRPath" 
    LOG_SUCCESS "Server Private Key '${ServerKeyPath##*/}' And CSR '${ServerCSRPath##*/}' Generation Is Completed."
fi

LOG_STEP "Generating Server Certificate With File Name: '${ServerCertPath##*/}'."
CA_KEY_PASSWORD="$Password" openssl x509 -req \
  -in "$ServerCSRPath" \
  -CA "$CaCertPath" \
  -CAkey "$CaKeyPath" \
  -CAcreateserial \
  -days 365 \
  -sha256 \
  -extfile "$ServerConfigPath" \
  -extensions v3_sign \
  -out "$ServerCertPath" \
  -passin env:CA_KEY_PASSWORD
LOG_SUCCESS "Server Certificate With File Name '${ServerCertPath##*/}' Generation Is Complete."

LOG_STEP "Generating Server PFX Certificate With File Name '${ServerPfxPath##*/}.'"
CA_KEY_PASSWORD="$Password" openssl pkcs12 -export \
  -out "$ServerPfxPath" \
  -inkey "$ServerKeyPath" \
  -in "$ServerCertPath" \
  -certfile "$CaCertPath" \
  -passout env:CA_KEY_PASSWORD
LOG_SUCCESS "Server PFX Certificate With File Name: '${ServerPfxPath##*/}'"

LOG_STEP "Exporting PFX Certificate Password Using File Name: '${ServerEnvPath##*/}'"
touch "$ServerEnvPath"
chmod 600 "$ServerEnvPath"
echo "ASPNETCORE_Kestrel__Certificates__Default__Password=$Password" > "$ServerEnvPath"
LOG_SUCCESS "Exported PFX Certificate Password To File Name '${ServerEnvPath##*/}' Completed."

if [[ -f "$ClientKeyPath" ]] && [ "$FullReload" = false ]; then
    LOG_INFO "Client Private Key Already Exists. Skipping Client Private Key Generation."
else
    LOG_STEP "Generating Client Private Key '${ClientKeyPath##*/}' And CSR '${ClientCSRPath##*/}'."
    openssl req -new \
    -newkey rsa:2048 \
    -noenc \
    -keyout "$ClientKeyPath" \
    -config "$ClientConfigPath" \
    -out "$ClientCSRPath" 
    LOG_SUCCESS "Client Private Key '${ClientKeyPath##*/}' And CSR '${ClientCSRPath##*/}' Generation Is Complete."
fi

LOG_STEP "Generating Client Certificate '${ClientCertPath##*/}'."
CA_KEY_PASSWORD="$Password" openssl x509 -req \
-in "$ClientCSRPath" \
-CA "$CaCertPath" \
-CAkey "$CaKeyPath" \
-CAcreateserial \
-days 365 \
-sha256 \
-extfile "$ClientConfigPath" \
-extensions v3_sign \
-out "$ClientCertPath" \
-passin env:CA_KEY_PASSWORD
LOG_SUCCESS "Client Certificate '${ClientCertPath##*/}' Generation Completed."

LOG_STEP "Verifying Server Certificate '${ServerKeyPath##*/}' With CA Certificate '${CaCertPath##*/}'."
openssl verify -CAfile "$CaCertPath" "$ServerCertPath"
LOG_SUCCESS "Server Certificate '${ServerKeyPath##*/}' Verified With CA Certificate '${CaCertPath##*/}'."

LOG_STEP "Verifying PFX Certificate '${ServerPfxPath##*/}' With CA Certificate '${CaCertPath}'."
CA_KEY_PASSWORD="$Password" openssl pkcs12 -in "$ServerPfxPath" \
  -clcerts -nokeys -passin env:CA_KEY_PASSWORD | \
  openssl verify -CAfile "$CaCertPath"
LOG_SUCCESS "Server PFX Certificate '${ServerPfxPath##*/}' Verified With CA Certificate '${CaCertPath##*/}'."

LOG_STEP "Verifying Client Certificate '${ClientCertPath##*/}' With CA Certificate '${CaCertPath}'."
openssl verify -CAfile "$CaCertPath" "$ClientCertPath"
LOG_SUCCESS "Client Certificate '${ClientCertPath##*/}' Verified With CA Certificate '${CaCertPath##*/}'."

exit "${EXIT_OK}"
