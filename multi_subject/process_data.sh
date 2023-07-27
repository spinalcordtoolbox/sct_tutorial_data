#!/bin/bash
#
# Process data. This script is designed to be run in the folder for a single subject, however 'sct_run_batch' can be
# used to run this script multiple times in parallel across a multi-subject BIDS dataset.
#
# This script only deals with T2w and MT images for example purpose. For a more comprehensive qMRI analysis, see for
# example this script: https://github.com/spine-generic/spine-generic/blob/master/process_data.sh
#
# Usage:
#   ./process_data.sh <SUBJECT>
#
# Example:
#   ./process_data.sh sub-03
#
# Author: Julien Cohen-Adad

# The following global variables are retrieved from the caller sct_run_batch
# but could be overwritten by uncommenting the lines below:
# PATH_DATA_PROCESSED="~/data_processed"
# PATH_RESULTS="~/results"
# PATH_LOG="~/log"
# PATH_QC="~/qc"


# BASH SETTINGS
# ======================================================================================================================

# Uncomment for full verbose
# set -v

# Immediately exit if error
set -e

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT


# CONVENIENCE FUNCTIONS
# ======================================================================================================================

label_if_does_not_exist() {
  ###
  #  This function checks if a manual label file already exists, then:
  #     - If it does, copy it locally.
  #     - If it doesn't, perform automatic labeling.
  #   This allows you to add manual labels on a subject-by-subject basis without disrupting the pipeline.
  ###
  local file="${1}"
  local file_seg="${2}"
  # Update global variable with segmentation file name
  FILELABEL="${file}"_labels
  FILELABELMANUAL="${PATH_DATA}"/derivatives/labels/"${SUBJECT}"/anat/"${FILELABEL}"-manual.nii.gz
  echo "Looking for manual label: ${FILELABELMANUAL}"
  if [[ -e "${FILELABELMANUAL}" ]]; then
    echo "Found! Using manual labels."
    rsync -avzh "${FILELABELMANUAL}" "${FILELABEL}".nii.gz
  else
    echo "Not found. Proceeding with automatic labeling."
    # Generate labeled segmentation
    sct_label_vertebrae -i "${file}".nii.gz -s "${file_seg}".nii.gz -c t2 -qc "${PATH_QC}" -qc-subject "${SUBJECT}"
    # Create labels in the cord at C3 and C5 mid-vertebral levels
    sct_label_utils -i "${file_seg}"_labeled.nii.gz -vert-body 3,5 -o "${FILELABEL}".nii.gz
  fi
}

segment_if_does_not_exist() {
  ###
  #  This function checks if a manual spinal cord segmentation file already exists, then:
  #    - If it does, copy it locally.
  #    - If it doesn't, perform automatic spinal cord segmentation.
  #  This allows you to add manual segmentations on a subject-by-subject basis without disrupting the pipeline.
  ###
  local file="${1}"
  local contrast="${2}"
  # Update global variable with segmentation file name
  FILESEG="${file}"_seg
  FILESEGMANUAL="${PATH_DATA}"/derivatives/labels/"${SUBJECT}"/anat/"${FILESEG}"-manual.nii.gz
  echo
  echo "Looking for manual segmentation: ${FILESEGMANUAL}"
  if [[ -e "${FILESEGMANUAL}" ]]; then
    echo "Found! Using manual segmentation."
    rsync -avzh "${FILESEGMANUAL}" "${FILESEG}".nii.gz
    sct_qc -i "${file}".nii.gz -s "${FILESEG}".nii.gz -p sct_deepseg_sc -qc "${PATH_QC}" -qc-subject "${SUBJECT}"
  else
    echo "Not found. Proceeding with automatic segmentation."
    # Segment spinal cord
    sct_deepseg_sc -i "${file}".nii.gz -c "${contrast}" -qc "${PATH_QC}" -qc-subject "${SUBJECT}"
  fi
}


# SCRIPT STARTS HERE
# ======================================================================================================================

# Retrieve input params
SUBJECT="${1}"

# get starting time:
start="$(date +%s)"

# Display useful info for the log, such as SCT version, RAM and CPU cores available
sct_check_dependencies -short

# Go to folder where data will be copied and processed
cd "${PATH_DATA_PROCESSED}"
# Copy source images
rsync -avzh "${PATH_DATA}"/"${SUBJECT}" .


# T2w
# ======================================================================================================================
cd "${SUBJECT}"/anat/
file_t2="${SUBJECT}"_T2w
# Segment spinal cord (only if it does not exist)
segment_if_does_not_exist "${file_t2}" "t2"
file_t2_seg="${FILESEG}"
# Create labels in the cord at C2 and C5 mid-vertebral levels (only if it does not exist)
label_if_does_not_exist "${file_t2}" "${file_t2_seg}"
file_label="${FILELABEL}"
# Register to template
sct_register_to_template -i "${file_t2}".nii.gz -s "${file_t2_seg}".nii.gz -l "${file_label}".nii.gz -c t2 \
                         -param step=1,type=seg,algo=centermassrot:step=2,type=im,algo=syn,iter=5,slicewise=1,metric=CC,smooth=0 \
                         -qc "${PATH_QC}"
# Warp template
# Note: we don't need the white matter atlas at this point, therefore use flag "-a 0"
sct_warp_template -d "${file_t2}".nii.gz -w warp_template2anat.nii.gz -a 0 -ofolder label_T2w -qc "${PATH_QC}"
# Compute average CSA between C2 and C3 levels (append across subjects)
sct_process_segmentation -i "${file_t2_seg}".nii.gz -vert 2:3 -vertfile label_T2w/template/PAM50_levels.nii.gz \
                         -o "${PATH_RESULTS}"/CSA.csv -append 1 -qc "${PATH_QC}"

# MT
# ======================================================================================================================
file_mt1="${SUBJECT}"_acq-MTon_MTS
file_mt0="${SUBJECT}"_acq-MToff_MTS
# Segment spinal cord
segment_if_does_not_exist "${file_mt1}" "t2s"
file_mt1_seg="${FILESEG}"
# Create mask
sct_create_mask -i "${file_mt1}".nii.gz -p centerline,"${file_mt1_seg}".nii.gz -size 45mm
# Crop data for faster processing
sct_crop_image -i "${file_mt1}".nii.gz -m "mask_${file_mt1}".nii.gz -o "${file_mt1}"_crop.nii.gz
sct_crop_image -i "${file_mt1_seg}".nii.gz -m "mask_${file_mt1}".nii.gz -o "${file_mt1}"_crop_seg.nii.gz
file_mt1="${file_mt1}"_crop
# Register mt0->mt1
# Tips: here we only use rigid transformation because both images have very
# similar sequence parameters. We don't want to use SyN/BSplineSyN to avoid
# introducing spurious deformations.
sct_register_multimodal -i "${file_mt0}".nii.gz -d "${file_mt1}".nii.gz \
                        -param step=1,type=im,algo=rigid,slicewise=1,metric=CC \
                        -x spline -qc "${PATH_QC}"
# Register template->mt1
# Tips: here we only use the segmentations due to poor SC/CSF contrast at the bottom slice.
# Tips: First step: slicereg based on images, with large smoothing to capture
# potential motion between anat and mt, then at second step: bpslinesyn in order to
# adapt the shape of the cord to the mt modality (in case there are distortions between anat and mt).
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t2.nii.gz \
                        -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz \
                        -d "${file_mt1}".nii.gz \
                        -dseg "${file_mt1}"_seg.nii.gz \
                        -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 \
                        -initwarp warp_template2anat.nii.gz \
                        -initwarpinv warp_anat2template.nii.gz \
                        -qc "${PATH_QC}"
# Rename warping fields for clarity
mv warp_PAM50_t22"${file_mt1}".nii.gz warp_template2mt.nii.gz
mv warp_"${file_mt1}"2PAM50_t2.nii.gz warp_mt2template.nii.gz
# Warp template
sct_warp_template -d "${file_mt1}".nii.gz -w warp_template2mt.nii.gz -ofolder label_MT -qc "${PATH_QC}"
# Compute mtr
sct_compute_mtr -mt0 "${file_mt0}"_reg.nii.gz -mt1 "${file_mt1}".nii.gz
# compute MTR in dorsal columns between levels C2 and C5 (append across subjects)
sct_extract_metric -i mtr.nii.gz -f label_MT/atlas -l 53 -vert 2:5 -vertfile label_MT/template/PAM50_levels.nii.gz \
                   -method map -o "${PATH_RESULTS}/MTR_in_DC.csv" -append 1

# Verify presence of output files and write log file if error
# ======================================================================================================================
FILES_TO_CHECK=(
  "${file_t2_seg}".nii.gz
  mtr.nii.gz
)
for file in "${FILES_TO_CHECK[@]}"; do
  if [ ! -e "${file}" ]; then
    echo "${SUBJECT}/${file} does not exist" >> "${PATH_LOG}/error.log"
  fi
done

# Display useful info for the log
end="$(date +%s)"
runtime="$((end-start))"
echo
echo "~~~"
echo "SCT version: $(sct_version)"
echo "Ran on:      $(uname -nsr)"
echo "Duration:    $((runtime / 3600))hrs $(( (runtime / 60) % 60))min $((runtime % 60))sec"
echo "~~~"
