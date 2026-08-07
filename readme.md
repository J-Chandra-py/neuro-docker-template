# Containerized Neuroimaging Processing Template

**Implementation: DWI Preprocessing Pipeline**

This repository provides a Dockerized pipeline for preprocessing Diffusion-Weighted Imaging (DWI) data, utilizing FSL (`eddy_cuda`), MRtrix3, and ANTs for denoising, artifact removal, and bias field correction.

Local neuroimaging setups often face dependency hurdles, such as **MRtrix setup on Linux** complexities or **N4BiasFieldCorrection errors** from **compile from source issues** on newer systems like **Ubuntu 24.04**. This container provides a reproducible environment using pre-compiled binaries. Additionally, its entrypoint automatically resolves common Docker **user permission issues** by restoring correct **file ownerships** for host-mounted outputs.

## Prerequisites

* **Docker** installed.
* **NVIDIA GPU** with compatible drivers.
* **NVIDIA Container Toolkit** installed (required for `eddy_cuda`).

## 1. Build the Image

Run this command in the directory containing your `Dockerfile` and scripts:

```bash
docker build -t dwi_pipeline:1.02 .

```

## 2. Run the Pipeline

Mount your local input (BIDS) and output directories. The `-e LOCAL_USER` variable allows the container to read inputs as root while automatically assigning proper ownership to the generated outputs.

```bash
docker run --rm -it --gpus all \
  -v /path/to/your/bids_data:/bids_data \
  -v /path/to/your/output_data:/deriv_data \
  -e LOCAL_USER=$(id -u):$(id -g) \
  dwi_pipeline:1.02

```

*Append `-e TEST_SUBJECTS=1` to the command above to run a single-subject test.*

## Input Data Structure

The pipeline requires a standard BIDS directory structure. Each subject's `dwi` folder must contain:

1. `*.nii.gz` (Raw DWI image)
2. `*.bval` (b-values)
3. `*.bvec` (b-vectors)
4. `acqparams.txt` (FSL Eddy acquisition parameters)

*Subjects missing any of these files will be skipped.*

## Outputs & Logging

Results are written to the mapped output directory:

* **`processing_status.csv`**: Master list of successful, failed, or skipped subjects.
* **`/logs`**: Individual processing logs.
* **`/skipped`**: Error details for subjects lacking required inputs.

## References

If you utilize this pipeline in published research, please cite the core tools:

**FSL & Eddy:**

* Jenkinson, M., et al. (2012). FSL. *NeuroImage*, 62(2), 782-790.
* Andersson, J. L. R., & Sotiropoulos, S. N. (2016). An integrated approach to correction for off-resonance effects and subject movement in diffusion MR imaging. *NeuroImage*, 125, 1063-1078.

**MRtrix3:**

* Tournier, J. D., et al. (2019). MRtrix3: A fast, flexible and open software framework for medical image processing and visualisation. *NeuroImage*, 202, 116137.

**ANTs (N4 Bias Field Correction):**

* Tustison, N. J., et al. (2010). N4ITK: improved N3 bias correction. *IEEE Transactions on Medical Imaging*, 29(6), 1310-1320.

## Keywords

`ANTs on Linux`, `MRtrix setup on Linux`, `N4BiasFieldCorrection error Ubuntu 24.04`, `compile from source issues`, `eddy_cuda Docker`, `DWI preprocessing pipeline`, `neuroimaging container`, `Docker user permission issue`, `Docker file ownerships`

---

**Note:** The Documentation in this repository were developed and structured with the assistance of AI, with frequent reviewing.
