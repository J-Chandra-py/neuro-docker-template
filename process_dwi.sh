#!/usr/bin/env bash
set -u

# Pipeline based on MRtrix3 and FSL/ANTs; DWI processing logic contributed by @MajidRamedani, DZNE.
# DWI preprocessing on BIDS dwi folders.
# Keeps final preprocessed NIfTI + gradients, acqparams.txt, logs, and selected eddy QC text files.
# Logs overall subject status (SUCCESS, FAILED, SKIPPED) to processing_status.csv

# Default paths correspond to the internal Docker volume mounts
BIDS_DIR="${BIDS_DIR:-/bids_data}"
DERIV_DIR="${DERIV_DIR:-/deriv_data}"
LOG_DIR="${DERIV_DIR}/logs"
PIPELINE_LOG="${LOG_DIR}/pipeline.log"
SKIPPED_DIR="${DERIV_DIR}/skipped"
SKIPPED_LOG="${SKIPPED_DIR}/skipped_missing_acqparams.csv"
STATUS_LOG="${DERIV_DIR}/processing_status.csv"
SUBJECTS="${SUBJECTS:-}"

trap 'echo -e "\n[!] Pipeline interrupted by user! Aborting..."; exit 130' INT TERM

mkdir -p "${LOG_DIR}"
mkdir -p "${SKIPPED_DIR}"

echo "$(date): start BIDS_DIR=${BIDS_DIR} DERIV_DIR=${DERIV_DIR}" | tee "${PIPELINE_LOG}"
echo "subject,reason,dwi_dir,acqparams_path" > "${SKIPPED_LOG}"
echo "subject,status,info" > "${STATUS_LOG}"

TEST_SUBJECTS="${TEST_SUBJECTS:-0}"
CLEAN_INTERMEDIATES="${CLEAN_INTERMEDIATES:-1}"


TOTAL=0
SUCCESS=0
FAIL=0
PROCESSED=0

if [ -n "${SUBJECTS}" ]; then
    subject_list=$(for s in ${SUBJECTS}; do printf '%s\n' "${s}"; done)
else
    subject_list=$(for d in "${BIDS_DIR}"/sub-*; do [ -d "${d}" ] && basename "${d}"; done | sort)
fi

for subject in ${subject_list}; do
    subject_dir="${BIDS_DIR}/${subject}/"
    [ -d "${subject_dir}" ] || continue

    if [ "${TEST_SUBJECTS}" -gt 0 ] && [ "${PROCESSED}" -ge "${TEST_SUBJECTS}" ]; then
        echo "Test mode: reached ${TEST_SUBJECTS} subject(s), stopping." | tee -a "${PIPELINE_LOG}"
        break
    fi
    [ -d "${subject_dir}" ] || continue
    subject=$(basename "${subject_dir}")
    dwi_src_dir="${subject_dir}dwi"
    
    if [ ! -d "${dwi_src_dir}" ]; then
        echo "${subject},SKIPPED,missing_dwi_folder" >> "${STATUS_LOG}"
        continue
    fi

    nii=$(find "${dwi_src_dir}" -maxdepth 1 -name "*.nii.gz" -type f \
          -exec ls -S {} + 2>/dev/null | head -n 1)
    
    if [ -z "${nii}" ]; then
        echo "${subject},SKIPPED,missing_nifti" >> "${STATUS_LOG}"
        continue
    fi

    bval="${nii%.nii.gz}.bval"
    bvec="${nii%.nii.gz}.bvec"
    acqp_src="${dwi_src_dir}/acqparams.txt"

    if [ ! -f "${bval}" ] || [ ! -f "${bvec}" ]; then
        echo "SKIP ${subject}: missing bval/bvec" | tee -a "${PIPELINE_LOG}"
        echo "${subject},SKIPPED,missing_bval_bvec" >> "${STATUS_LOG}"
        continue
    fi
    if [ ! -f "${acqp_src}" ]; then
        echo "SKIP ${subject}: missing dwi/acqparams.txt" | tee -a "${PIPELINE_LOG}"
        echo "${subject},missing_acqparams,${dwi_src_dir},${acqp_src}" >> "${SKIPPED_LOG}"
        echo "${subject},SKIPPED,missing_acqparams" >> "${STATUS_LOG}"
        {
            echo "subject: ${subject}"
            echo "reason: missing dwi/acqparams.txt"
            echo "dwi_dir: ${dwi_src_dir}"
            echo "acqparams_path: ${acqp_src}"
        } > "${SKIPPED_DIR}/${subject}_missing_acqparams.txt"
        continue
    fi

    TOTAL=$((TOTAL + 1))
    PROCESSED=$((PROCESSED + 1))

    out_dir="${DERIV_DIR}/${subject}/dwi"
    mkdir -p "${out_dir}"

    log="${LOG_DIR}/${subject}_dwi_preproc.log"
    bn=$(basename "${nii}" .nii.gz)

    {
        echo "=== ${subject} ==="
        echo "Started: $(date)"
        echo "Input:    ${nii}"
        echo "Output:   ${out_dir}"
    } > "${log}"

    echo "RUN ${subject}" | tee -a "${PIPELINE_LOG}"

    (
        set -e
        cd "${out_dir}"

        mrconvert "${nii}" "${bn}.mif" \
            -fslgrad "${bvec}" "${bval}" \
            -force >> "${log}" 2>&1

        dwidenoise "${bn}.mif" "${bn}_denoised.mif" \
            -force >> "${log}" 2>&1

        mrdegibbs "${bn}_denoised.mif" "${bn}_degibbs.mif" \
            -force >> "${log}" 2>&1

        mrconvert "${bn}_degibbs.mif" "${bn}_degibbs.nii.gz" \
            -export_grad_fsl "${bn}_degibbs.bvec" "${bn}_degibbs.bval" \
            -force >> "${log}" 2>&1

        fslroi "${bn}_degibbs.nii.gz" "${bn}_b0.nii.gz" 0 1 >> "${log}" 2>&1

        bet "${bn}_b0.nii.gz" "${bn}_b0_brain" \
            -f 0.3 -m >> "${log}" 2>&1

        NVOL=$(fslval "${bn}_degibbs.nii.gz" dim4)
        rm -f index.txt
        for ((i=1; i<=NVOL; i++)); do printf "1 "; done > index.txt
        echo "" >> index.txt

        cp "${acqp_src}" acqparams.txt
        echo "acqparams source: BIDS" >> "${log}"

        eddy_cuda \
            --imain="${bn}_degibbs.nii.gz" \
            --mask="${bn}_b0_brain_mask.nii.gz" \
            --acqp=acqparams.txt \
            --index=index.txt \
            --bvecs="${bn}_degibbs.bvec" \
            --bvals="${bn}_degibbs.bval" \
            --out="${bn}_eddy" \
            --data_is_shelled \
            --verbose >> "${log}" 2>&1

        mrconvert "${bn}_eddy.nii.gz" "${bn}_eddy.mif" \
            -fslgrad "${bn}_eddy.eddy_rotated_bvecs" "${bn}_degibbs.bval" \
            -force >> "${log}" 2>&1

        dwibiascorrect ants \
            "${bn}_eddy.mif" \
            "${bn}_preprocessed.mif" \
            -force >> "${log}" 2>&1

        mrconvert "${bn}_preprocessed.mif" "${bn}_preprocessed.nii.gz" \
            -export_grad_fsl "${bn}_preprocessed.bvec" "${bn}_preprocessed.bval" \
            -force >> "${log}" 2>&1

        if [ "${CLEAN_INTERMEDIATES}" = "1" ]; then
            rm -f "${bn}.mif"
            rm -f "${bn}_denoised.mif"
            rm -f "${bn}_degibbs.mif"
            rm -f "${bn}_degibbs.nii.gz"
            rm -f "${bn}_degibbs.bval"
            rm -f "${bn}_degibbs.bvec"
            rm -f "${bn}_b0.nii.gz"
            rm -f "${bn}_b0_brain.nii.gz"
            rm -f "${bn}_b0_brain_mask.nii.gz"
            rm -f "${bn}_eddy.nii.gz"
            rm -f "${bn}_eddy.mif"
            rm -f "${bn}_preprocessed.mif"

            rm -f "${bn}_eddy.eddy_outlier_map"
            rm -f "${bn}_eddy.eddy_outlier_n_sqr_stdev_map"
            rm -f "${bn}_eddy.eddy_outlier_n_stdev_map"
            rm -f "${bn}_eddy.eddy_post_eddy_shell_alignment_parameters"
            rm -f "${bn}_eddy.eddy_post_eddy_shell_PE_translation_parameters"
            rm -f "${bn}_eddy.eddy_values_of_all_input_parameters"
        fi

    ) && {
        echo "Completed: $(date)" >> "${log}"
        echo "DONE ${subject}" | tee -a "${PIPELINE_LOG}"
        echo "${subject},SUCCESS,Completed without errors" >> "${STATUS_LOG}"
        SUCCESS=$((SUCCESS + 1))
    } || {
        echo "FAILED ${subject} (see ${log})" | tee -a "${PIPELINE_LOG}"
        echo "${subject},FAILED,Check log: ${log}" >> "${STATUS_LOG}"
        FAIL=$((FAIL + 1))
    }

done

echo "$(date): done total=${TOTAL} success=${SUCCESS} failed=${FAIL}" | tee -a "${PIPELINE_LOG}"
echo "Master Status Log: ${STATUS_LOG}" | tee -a "${PIPELINE_LOG}"
