# Use an NVIDIA CUDA base image to support eddy_cuda
FROM nvidia/cuda:11.8.0-runtime-ubuntu20.04

# Add Maintainer and Image Metadata
LABEL maintainer="Jaya C. Terli, 2026"
LABEL version="1.02"
LABEL description="Preprocessing Pipeline using FSL, MRtrix3, and ANTs"

# Set environment variables to prevent interactive prompts during apt installs
ENV DEBIAN_FRONTEND="noninteractive"
ENV LANG="en_GB.UTF-8"
ENV LC_ALL="C"

# 1. Install basic system utilities
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      python3 wget git file dc ca-certificates \
      libquadmath0 libgomp1 && \
    rm -rf /var/lib/apt/lists/*

# 2. Install FSL (Pre-compiled via its own installer)
ENV FSLDIR="/usr/local/fsl"
RUN wget https://fsl.fmrib.ox.ac.uk/fsldownloads/fslconda/releases/fslinstaller.py && \
    python3 ./fslinstaller.py -d $FSLDIR -q && \
    rm fslinstaller.py

# 3. Install Miniforge (Community Conda without ToS blocks), ANTs, and MRtrix3
ENV CONDA_DIR="/opt/conda"
ENV PATH="$CONDA_DIR/bin:$PATH"
RUN wget --quiet https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O ~/miniforge.sh && \
    bash ~/miniforge.sh -b -p $CONDA_DIR && \
    rm ~/miniforge.sh && \
    # Install both ANTs and MRtrix3 directly from their conda channels
    conda install -y -c conda-forge -c mrtrix3 ants mrtrix3 && \
    conda clean -ya

# 4. Set final PATH mapping
# We put FSL at the end of the PATH so its internal libraries don't clash with Conda
ENV PATH="$FSLDIR/share/fsl/bin:$FSLDIR/bin:$PATH"

# 5. Copy scripts into the image
COPY process_dwi.sh /usr/local/bin/process_dwi.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# 6. Make them executable for all users
RUN chmod a+rx /usr/local/bin/process_dwi.sh && \
    chmod a+rx /usr/local/bin/entrypoint.sh

# 7. Setup Entrypoint and Default Command
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["process_dwi.sh"]