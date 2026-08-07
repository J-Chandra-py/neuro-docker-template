#!/usr/bin/env bash

# ====================================================================
# AUTO-CHOWN TRAP
# Fixes ownership of output files when the container exits.
# ====================================================================
cleanup() {
    DERIV_DIR="${DERIV_DIR:-/deriv_data}"

    if [ -n "${LOCAL_USER:-}" ]; then
        echo "Fixing file ownership in ${DERIV_DIR} to ${LOCAL_USER}..."
        chown -R "${LOCAL_USER}" "${DERIV_DIR}" || true
    fi
}
trap cleanup EXIT INT TERM
# ====================================================================

# Source the FSL environment so commands like eddy_cuda work
. /usr/local/fsl/etc/fslconf/fsl.sh

# Execute the command passed to the docker container 
"$@"