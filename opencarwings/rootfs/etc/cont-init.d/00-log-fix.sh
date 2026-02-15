#!/usr/bin/with-contenv bashio
# Redefine bashio logging to support full-line colorization matching Django/App format

function bashio::log._color() {
    local level="$1"
    local message="$2"
    local tag="${3:-bash}"  # Default to [bash] if no tag provided
    
    # Aesthetic Color Constants (Basic ANSI for maximum compatibility)
    local GREEN='\033[32m'   # Level: INFO
    local YELLOW='\033[33m'  # Level: WARNING
    local RED='\033[31m'     # Level: ERROR
    local GRAY='\033[35m'     # Level: DEBUG/OTHER (Purple)
    local NC='\033[0m'       # No Color

    local LEVEL_COLOR="${GRAY}"
    case "${level}" in
        "info")    LEVEL_COLOR="${GREEN}" ;;
        "warning") LEVEL_COLOR="${YELLOW}" ;;
        "error")   LEVEL_COLOR="${RED}" ;;
        "debug")   LEVEL_COLOR="${GRAY}" ;;
    esac

    local LEVEL_LABEL=$(echo "${level}" | tr '[:lower:]' '[:upper:]')
    echo -e "[$(date +'%H:%M:%S')] ${LEVEL_COLOR}${LEVEL_LABEL}: [${tag}] ${message}${NC}"
}

function bashio::log.info() { bashio::log._color "info" "$1" "${2:-bash}"; }
function bashio::log.warning() { bashio::log._color "warning" "$1" "${2:-bash}"; }
function bashio::log.error() { bashio::log._color "error" "$1" "${2:-bash}"; }
function bashio::log.debug() { bashio::log._color "debug" "$1" "${2:-bash}"; }
