#!/bin/bash
#
# Example of commands to process multi-parametric data of the spinal cord
# For information about acquisition parameters, see: www.spinalcordmri.org/protocols
#
# Notes:
#   - Many of the commands in this script are commented out (start with "# "). These commands won't be run by default,
#     as many of them involve manual steps (e.g. via an interactive pop-up interface), or may involve data-specific
#     configuration. Often these commands correspond to the "try at home" slides in the SCT Course slide deck,
#     (denoted by a "red circle" in the top-right corner of the corresponding slide). Feel free to "uncomment" the
#     commands by removing the "# " symbol at the start of the line, and experiment with them on your own data.
#   - The parameters were chosen to suit SCT's sample tutorial data. With your data,
#     it is worthwhile to explore the various parameters and tweak them to your situation.
#
# tested with Spinal Cord Toolbox (v6.5)

# Script utilities
# ======================================================================================================================

# If a command fails, set -e will make the whole script exit, instead of just resuming on the next line
set -e

# Exit if user presses CTRL+C (Linux) or CMD+C (OSX)
trap "echo Caught Keyboard Interrupt within script. Exiting now.; exit" INT

# display starting time:
echo -e "\nStarted at: $(date +%x_%r)"

# If fsleyes hasn't been installed, provide a subsitute function to avoid crashing the script
# Source: https://unix.stackexchange.com/a/497540
if ! command -v fsleyes > /dev/null; then
  fsleyes() {
    printf 'WARNING: FSLeyes is not installed, so the following command was skipped:\nfsleyes %s\n' "${*@Q}";
  };
fi



# ======================================================================================================================
# START OF SCRIPT
# ======================================================================================================================

# Spinal cord segmentation
# ======================================================================================================================

# Go to T2 folder
cd data/t2
# Spinal cord segmentation (using the new 2024 contrast-agnostic method)
sct_deepseg spinalcord -i t2.nii.gz -qc ~/qc_singleSubj
# The default output is t2_seg.nii.gz
# You can also choose your own output filename using the “-o” argument
sct_deepseg spinalcord -i t2.nii.gz -o test/t2_seg_2.nii.gz

# To check the QC report, use your web browser to open the file qc_singleSubj/qc/index.html, which has been created in
# your home directory

# View the rest of the `sct_deepseg` tasks
sct_deepseg -h
# See also: https://spinalcordtoolbox.com/stable/user_section/command-line/sct_deepseg.html



# Vertebral labeling
# ======================================================================================================================

# Vertebral disc labeling
sct_deepseg spine -i t2.nii.gz -label-vert 1 -qc ~/qc_singleSubj

# Full spinal segmentation (Vertebrae, Intervertebral discs, Spinal cord and Spinal canal)
# Segment using totalspineseg
sct_deepseg spine -i t2.nii.gz -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_step1_canal.nii.gz -cm YlOrRd -a 70.0 t2_step1_cord.nii.gz -cm YlOrRd -a 70.0 t2_totalspineseg_discs.nii.gz -cm subcortical -a 70.0 t2_step1_output.nii.gz -cm subcortical -a 70.0 t2_step2_output.nii.gz -cm subcortical -a 70.0 &
# Check QC report: Go to your browser and do "refresh".

# Optionally, you can use the generated disc labels to create a labeled segmentation
# Note: This approach is no longer recommended. Instead, use the disc labels directly in subsequent commands (e.g. `sct_process_segmentation`).
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2 -discfile t2_totalspineseg_discs.nii.gz
# FIXME: Remove this command once the web tutorials are updated to no longer use labeled segmentations



# Shape-based analysis
# ======================================================================================================================

# Compute cross-sectional area (CSA) of spinal cord and average it across levels C3 and C4
sct_process_segmentation -i t2_seg.nii.gz -vert 3:4 -discfile t2_totalspineseg_discs.nii.gz -o csa_c3c4.csv

#######################################################################################################################
# FIXME: Metric 1/8: [t2/csa_c2c3.csv-0-MEAN(area)]
# Notes:
#   - We have a corresponding command that computes `csa_c3c4.csv` (see above).
#      - The above `batch_single_subject.sh` command uses the disc labels directly.
#      - By comparison, the old `batch_processing.sh` commands rely on the the warped template (registered using the vert labels)
#   - In summary, the old metric values we are testing are wholly incompatible with our current up-to-date pipelines.
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2
sct_label_utils -i t2_seg_labeled.nii.gz -vert-body 2,5 -o labels_vert.nii.gz
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -l labels_vert.nii.gz -c t2
sct_warp_template -d t2.nii.gz -w warp_template2anat.nii.gz -a 0
sct_process_segmentation -i t2_seg.nii.gz -vert 2:3 -o csa_c2c3.csv
#######################################################################################################################

# Aggregate CSA value per level (including new anat-based symmetry metrics)
sct_process_segmentation -i t2_seg.nii.gz -anat t2.nii.gz -vert 3:4 -discfile t2_totalspineseg_discs.nii.gz -perlevel 1 -o csa_perlevel.csv
# Aggregate CSA value per slices
sct_process_segmentation -i t2_seg.nii.gz -z 30:35 -discfile t2_totalspineseg_discs.nii.gz -perslice 1 -o csa_perslice.csv

# A drawback of vertebral level-based CSA is that it doesn’t consider neck flexion and extension.
# To overcome this limitation, the CSA can instead be computed using the distance to a reference point.
# Here, we use the Pontomedullary Junction (PMJ), since the distance from the PMJ along the centerline
# of the spinal cord will vary depending on the position of the neck.
sct_detect_pmj -i t2.nii.gz -c t2 -qc ~/qc_singleSubj
# Check the QC to make sure PMJ was properly detected, then compute CSA using the distance from the PMJ:
sct_process_segmentation -i t2_seg.nii.gz -pmj t2_pmj.nii.gz -pmj-distance 64 -pmj-extent 30 -o csa_pmj.csv -qc ~/qc_singleSubj -qc-image t2.nii.gz

#######################################################################################################################
# FIXME: Metric 2/8: [t2/csa_pmj.csv-0-MEAN(area)]
# Notes:
#   - We have a corresponding command that computes `csa_pmj.csv` (see above).
#   - There is only a small discrepancy in `-pmj-distance`, and this is easily fixable.
sct_process_segmentation -i t2_seg.nii.gz -pmj t2_pmj.nii.gz -pmj-distance 60 -pmj-extent 30 -o csa_pmj.csv
#######################################################################################################################

# The above commands will output the metrics in the subject space (with the original image's slice numbers)
# However, you can get the corresponding slice number in the PAM50 space by using the flag `-normalize-PAM50 1`
sct_process_segmentation -i t2_seg.nii.gz -discfile t2_totalspineseg_discs.nii.gz -perslice 1 -normalize-PAM50 1 -o csa_PAM50.csv

#######################################################################################################################
# FIXME: Metric 3/8: [t2/csa_pam50.csv-38-MEAN(area)]
# Notes:
#   - We have a corresponding command that computes `csa_pam50.csv` (see above).
#     - The above `batch_single_subject.sh` command uses the disc labels directly.
#     - By comparison, the old `batch_processing.sh` commands relies on the `sct_label_vertebrae` seg for `-vertfile`.
#   - In summary, the old metric values we are testing are wholly incompatible with our current up-to-date pipelines.
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2
sct_process_segmentation -i t2_seg.nii.gz -vertfile t2_seg_labeled.nii.gz -perslice 1 -normalize-PAM50 1 -o csa_pam50.csv
#######################################################################################################################


# Quantifying spinal cord compression using maximum spinal cord compression (MSCC) and normalizing with database of healthy controls
# ======================================================================================================================
cd ../t2_compression
# Segment the spinal cord of the compressed spine
sct_deepseg spinalcord -i t2_compressed.nii.gz -qc ~/qc_singleSubj
# Label the vertebrae using the compressed spinal cord segmentation
sct_label_vertebrae -i t2_compressed.nii.gz -s t2_compressed_seg.nii.gz -c t2 -qc ~/qc_singleSubj
# Generate labels for each spinal cord compression site.
# Note: Normally this would be done manually using fsleyes' "Edit mode -> Create mask" functionality. (Uncomment below)
#
# fsleyes t2_compressed.nii.gz &
#
# However, since this is an automated script with example data, we will place the labels at known locations for the
# sake of reproducing the results in the tutorial.
sct_label_utils -i t2_compressed.nii.gz -create 30,152,99,1.0:30,156,118,1.0:30,157,140,1.0:31,160,159,1.0 -o t2_compressed_labels-compression.nii.gz
# Compute ratio between AP-diameter at level of compression vs. above/below
sct_compute_compression -i t2_compressed_seg.nii.gz -vertfile t2_compressed_seg_labeled.nii.gz -l t2_compressed_labels-compression.nii.gz -metric diameter_AP -normalize-hc 0 -o ap_ratio.csv
# Compute ratio of AP diameter, normalized with healthy controls using `-normalize-hc 1`.
sct_compute_compression -i t2_compressed_seg.nii.gz -vertfile t2_compressed_seg_labeled.nii.gz -l t2_compressed_labels-compression.nii.gz -metric diameter_AP -normalize-hc 1 -o ap_ratio_norm_PAM50.csv

# NB: All 5 of the metrics below use the T2 registration to template as an `-initwarp` step. This means that to reproduce
#     the old batch_processing.sh values, we need to use the old T2 warping fields, too. (See: "Metric 1/8" for the steps)
#     It's totally possible to move these commands to _after_ the revamped T2 registration step, but the values will be off:
#       - https://github.com/spinalcordtoolbox/sct_tutorial_data/commit/84139952c531ada90a901d9612ff7a8070bcc02f
#       - https://github.com/spinalcordtoolbox/spinalcordtoolbox/actions/runs/22780277293/job/67453420618?pr=5185

#######################################################################################################################
# FIXME: Metric 4/8: [t2s/csa_gm.csv-3-MEAN(area)]
# FIXME: Metric 5/8: [t2s/csa_wm.csv-3-MEAN(area)]
# Notes:
#   - We have corresponding commands that compute the GM/WM (see GM sections later on).
#     - For `batch_single_subject.sh`, we use the new `graymatter` method, and register using the WM seg with updated params.
#     - For `batch_processing.sh`, we use the old `sct_deepseg_gm` method, and register using the GM seg with outdated params.
cd ../t2s
sct_deepseg spinalcord -i t2s.nii.gz -qc ~/qc_singleSubj
sct_deepseg_gm -i t2s.nii.gz
sct_maths -i t2s_seg.nii.gz -sub t2s_gmseg.nii.gz -o t2s_wmseg.nii.gz
#   - We also have corresponding commands that compute the `csa_wm.csv`/`csa_gm.csv` (see above).
#     - For `batch_single_subject.sh`, we compute `-perslice 1` directly on the segmentation file.
#     - For `batch_processing.sh`, we compute `-perlevel 1` using the warped template.
#   - In summary, the old metric values we are testing are wholly incompatible with our current up-to-date pipelines.
sct_register_multimodal -i "$SCT_DIR/data/PAM50/template/PAM50_t2s.nii.gz" -iseg "$SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz" -d t2s.nii.gz -dseg t2s_seg.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,algo=syn,slicewise=1,iter=1,metric=CC -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2t2s.nii.gz -owarpinv warp_t2s2template.nii.gz
sct_warp_template -d t2s.nii.gz -w warp_template2t2s.nii.gz
sct_process_segmentation -i t2s_gmseg.nii.gz -vert 2:5 -perlevel 1 -o csa_gm.csv -centerline t2s_seg.nii.gz
sct_process_segmentation -i t2s_wmseg.nii.gz -vert 2:5 -perlevel 1 -o csa_wm.csv -centerline t2s_seg.nii.gz
#######################################################################################################################

#######################################################################################################################
# FIXME: Metric 6/8: [mt/mtr_in_wm.csv-0-MAP()]
# Notes:
#   - We have corresponding commands to compute the MTR (see MT sections later on).
#      - For `batch_single_subject.sh`, the mask is used directly for the `-m` argument of `sct_register_multimodal`.
#      - For `batch_processing.sh`, however, the mask is used to crop the image prior to registration.
cd ../mt
sct_get_centerline -i mt1.nii.gz -c t2
sct_create_mask -i mt1.nii.gz -p centerline,mt1_centerline.nii.gz -size 45mm
sct_crop_image -i mt1.nii.gz -m mask_mt1.nii.gz -o mt1_crop.nii.gz
sct_deepseg spinalcord -i mt1_crop.nii.gz
sct_register_multimodal -i mt0.nii.gz -d mt1_crop.nii.gz -dseg mt1_crop_seg.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -x spline
sct_compute_mtr -mt0 mt0_reg.nii.gz -mt1 mt1_crop.nii.gz
#   - We also have corresponding commands that compute the `mtr_in_wm.csv` file
#      - For `batch_single_subject.sh`, we A) use the mask during registration to template, B) we use the t2s for initwarp, and C) we don't aggregate the levels at all.
#      - For `batch_processing.sh`, however, A) use the cropped image during template registration, B) we use the t2 for initwarp, and C) we aggregate the MTR values across levels 2 to 5.
#   - In summary, the old metric values we are testing are wholly incompatible with our current up-to-date pipelines.
sct_register_multimodal -i "$SCT_DIR/data/PAM50/template/PAM50_t2.nii.gz" -iseg "$SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz" -d mt1_crop.nii.gz -dseg mt1_crop_seg.nii.gz -param step=1,type=seg,algo=slicereg,smooth=3:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2mt.nii.gz -owarpinv warp_mt2template.nii.gz
sct_warp_template -d mt1_crop.nii.gz -w warp_template2mt.nii.gz
sct_extract_metric -i mtr.nii.gz -method map -o mtr_in_wm.csv -l 51 -vert 2:5
#######################################################################################################################

#######################################################################################################################
# FIXME: Metric 7/8: [dmri/fa_in_cst.csv-0-WA()]
# FIXME: Metric 8/8: [dmri/fa_in_cst.csv-1-WA()]
#   - We have corresponding commands to compute the mask for motion correction (see dMRI sections later on).
#     - For `batch_single_subject.sh`, we currently segment the dMRI cord directly, then dilate it.
#     - For `batch_processing.sh`, we warp the T2 seg, then create the mask from that.
cd ../dmri
sct_dmri_separate_b0_and_dwi -i dmri.nii.gz -bvec bvecs.txt
sct_register_multimodal -i ../t2/t2_seg.nii.gz -d dmri_dwi_mean.nii.gz -identity 1 -x nn
sct_create_mask -i dmri_dwi_mean.nii.gz -p centerline,t2_seg_reg.nii.gz -size 35mm
#   - We also have corresponding commands to warp the template to the motion-corrected sequence (see dMRI sections later on).
#     - The process is basically the same (apart from the differing masks)
sct_dmri_moco -i dmri.nii.gz -bvec bvecs.txt -m mask_dmri_dwi_mean.nii.gz
sct_deepseg spinalcord -i dmri_moco_dwi_mean.nii.gz
sct_qc -i dmri.nii.gz -d dmri_moco.nii.gz -s dmri_moco_dwi_mean_seg.nii.gz -p sct_dmri_moco
sct_register_multimodal -i "$SCT_DIR/data/PAM50/template/PAM50_t1.nii.gz" -iseg "$SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz" -d dmri_moco_dwi_mean.nii.gz -dseg dmri_moco_dwi_mean_seg.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,smooth=1,iter=3 -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2dmri.nii.gz -owarpinv warp_dmri2template.nii.gz
sct_warp_template -d dmri_moco_dwi_mean.nii.gz -w warp_template2dmri.nii.gz
#   - Lastly, we also have a corresponding command to extract DTI metrics (see dMRI sections later on).
#     - For `batch_single_subject.sh`, we compute FA in the WM aggregated across levels.
#     - For `batch_processing.sh`, we compute FA in the CST, aggregated across slices.
sct_dmri_compute_dti -i dmri_moco.nii.gz -bval bvals.txt -bvec bvecs.txt
sct_extract_metric -i dti_FA.nii.gz -z 2:14 -method wa -l 4,5 -o fa_in_cst.csv
#######################################################################################################################


# Registration to template
# ======================================================================================================================
cd ../t2

# Create labels at C3 and T2 mid-vertebral levels. These labels are needed for template registration.
sct_label_utils -i t2_totalspineseg_discs.nii.gz -keep 3,9 -o t2_labels_vert.nii.gz
# Generate a QC report to visualize the two selected labels on the anatomical image
sct_qc -i t2.nii.gz -s t2_labels_vert.nii.gz -p sct_label_utils -qc ~/qc_singleSubj

# OPTIONAL: You might want to completely bypass sct_label_vertebrae and do the labeling manually. In that case, we
# provide a viewer to do so conveniently. In the example command below, we will create labels at the inter-vertebral
# discs C2-C3 (value=3), C3-C4 (value=4) and C4-C5 (value=5).
# sct_label_utils -i t2.nii.gz -create-viewer 3,4,5 -o labels_disc.nii.gz -msg "Place labels at the posterior tip of each inter-vertebral disc. E.g. Label 3: C2/C3, Label 4: C3/C4, etc."

# Register t2->template.
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -ldisc t2_labels_vert.nii.gz -c t2 -qc ~/qc_singleSubj
# Note: By default the PAM50 template is selected. You can also select your own template using flag -t.

# Register t2->template with modified parameters (advanced usage of `-param`)
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -ldisc t2_labels_vert.nii.gz -qc ~/qc_singleSubj -ofolder advanced_param -c t2 -param step=1,type=seg,algo=rigid:step=2,type=seg,metric=CC,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,metric=CC,algo=syn,slicewise=1,iter=2

# Register t2->template with large FOV (e.g. C2-L1) using `-ldisc` option
# sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -ldisc t2_totalspineseg_discs.nii.gz -c t2

# Register t2->template in compressed cord (example command)
# In case of highly compressed cord, the algo columnwise can be used, which allows for more deformation than bsplinesyn.
# NB: In the example below, the registration is done in the subject space (no straightening) using a single label point at disc C3-C4 (<LABEL_DISC>).
# sct_register_to_template -i <IMAGE> -s <SEGMENTATION> -ldisc <LABEL_DISC> -ref subject -param step=1,type=seg,
# algo=centermassrot:step=2,type=seg,algo=columnwise

# Warp template objects (T2, cord segmentation, vertebral levels, etc.). Here we use -a 0 because we don’t need the
# white matter atlas at this point.
sct_warp_template -d t2.nii.gz -w warp_template2anat.nii.gz -a 0 -qc ~/qc_singleSubj
# Note: A folder label/template/ is created, which contains template objects in the space of the subject. The file
#       info_label.txt lists all template files.

# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale -a 100.0 label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 50.0 label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 50.0 &



# Registering additional contrasts (MT registration to T2 template)
# ======================================================================================================================

# Go to mt folder
cd ../mt
# Segment cord
sct_deepseg spinalcord -i mt1.nii.gz -qc ~/qc_singleSubj

# Create a close mask around the spinal cord for more accurate registration (i.e. does not account for surrounding
# tissue which could move independently from the cord)
sct_create_mask -i mt1.nii.gz -p centerline,mt1_seg.nii.gz -size 35mm -f cylinder -o mask_mt1.nii.gz

# Register template->mt1. The flag -initwarp ../t2/warp_template2anat.nii.gz initializes the registration using the
# template->t2 transformation which was previously estimated
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t2.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz -d mt1.nii.gz -dseg mt1_seg.nii.gz -m mask_mt1.nii.gz -initwarp ../t2/warp_template2anat.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -owarp warp_template2mt.nii.gz -qc ~/qc_singleSubj
# Tips: Here we only use the segmentations (type=seg) to minimize the sensitivity of the registration procedure to
#       image artifacts.
# Tips: Step 1: algo=centermass to align source and destination segmentations, then Step 2: algo=bpslinesyn to adapt the
#       shape of the cord to the mt modality (in case there are distortions between the t2 and the mt scan).

# OPTIONAL: Registration with -initwarp requires pre-registration, but in some cases you won't have an anatomical image to do a pre-registration. So, as an alternative, you can register the template directly to a metric image. For that, you just need to create one or two labels in the metric space. For example, if you know that your FOV is centered at C3/C4 disc, then you can create a label automatically with:
# sct_label_utils -i mt1_seg.nii.gz -create-seg-mid 4 -o label_c3c4.nii.gz
# Then, you can register to the template.
# Note: In case the metric image has axial resolution with thick slices, we recommend to do the registration in the subject space (instead of the template space), without cord straightening.
# sct_register_to_template -i mt1.nii.gz -s mt1_seg.nii.gz -ldisc label_c3c4.nii.gz -ref subject -param step=1,type=seg,algo=centermassrot:step=2,type=seg,algo=bsplinesyn,slicewise=1

# Warp template
sct_warp_template -d mt1.nii.gz -w warp_template2mt.nii.gz -a 1 -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes mt1.nii.gz -cm greyscale -a 100.0 label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 50.0 label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 50.0 &



# Registering additional contrasts (MT0/MT1 coregistration to compute MTR)
# ======================================================================================================================

# Register mt0->mt1 using z-regularized slicewise translations (algo=slicereg)
# Note: Segmentation and mask can be re-used from "MT registration" section
sct_register_multimodal -i mt0.nii.gz -d mt1.nii.gz -dseg mt1_seg.nii.gz -m mask_mt1.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -x spline -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes mt1.nii.gz mt0_reg.nii.gz &
# Compute MTR
sct_compute_mtr -mt0 mt0_reg.nii.gz -mt1 mt1.nii.gz
# Note: MTR is given in percentage.



# Registering additional contrasts (T2 lumbar data)
# ======================================================================================================================
cd ../t2_lumbar

# Use lumbar-specific `sct_deepseg` model to segment the spinal cord
sct_deepseg sc_lumbar_t2 -i t2_lumbar.nii.gz -qc ~/qc_singleSubj

# Generate labels for the 2 spinal cord landmarks: cauda equinea ('99') and T9-T10 disc ('17')
# Note: Normally this would be done manually using fsleyes' "Edit mode -> Create mask" functionality. (Uncomment below)
#
# fsleyes t2.nii.gz &
#
# However, since this is an automated script with example data, we will place the labels at known locations for the
# sake of reproducing the results in the tutorial.
sct_label_utils -i t2_lumbar.nii.gz -create 27,76,187,17:27,79,80,60 -o t2_lumbar_labels.nii.gz -qc ~/qc_singleSubj

# generate a QC report for the lumbar labels
sct_qc -i t2_lumbar.nii.gz -s t2_lumbar_labels.nii.gz -p sct_label_utils -qc ~/qc_singleSubj

# Register the image to the template using segmentation and labels
sct_register_to_template -i t2_lumbar.nii.gz -s t2_lumbar_seg.nii.gz -ldisc t2_lumbar_labels.nii.gz -c t2 -qc ~/qc_singleSubj -param step=1,type=seg,algo=centermassrot:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,iter=3,slicewise=0:step=3,type=im,algo=syn,metric=CC,iter=3,slicewise=0



# Gray matter segmentation (GM/WM seg)
# ======================================================================================================================

# Go to T2*-weighted data, which has good GM/WM contrast and high in-plane resolution
cd ../t2s
# Segment gray matter (check QC report afterwards)
sct_deepseg graymatter -i t2s.nii.gz -o t2s_gmseg.nii.gz -qc ~/qc_singleSubj
# Spinal cord segmentation
sct_deepseg spinalcord -i t2s.nii.gz -qc ~/qc_singleSubj
# Subtract GM segmentation from cord segmentation to obtain WM segmentation
# Note that we use the flag -thr 0 in case some voxels in the GM segmentation are *not* included in the cord
# segmentation. That would results in voxels in the WM segmentation having the value “-1”, which would cause issues
# with the registration. 
sct_maths -i t2s_seg.nii.gz -sub t2s_gmseg.nii.gz -thr 0 -o t2s_wmseg.nii.gz



# Gray matter segmentation (Shape-based analysis and metric extraction)
# ======================================================================================================================

# Compute cross-sectional area (CSA) of the gray and white matter for all slices in the volume.
# Note: Here we use the flag -angle-corr 0, because we do not want to correct the computed CSA by the cosine of the
# angle between the cord centerline and the S-I axis: we assume that slices were acquired orthogonally to the cord.
sct_process_segmentation -i t2s_wmseg.nii.gz -o csa_wm_perslice.csv -perslice 1 -angle-corr 0
sct_process_segmentation -i t2s_gmseg.nii.gz -o csa_gm_perslice.csv -perslice 1 -angle-corr 0

# You can also use the binary masks to extract signal intensity from MRI data.
# The example below will show how to use the GM and WM segmentations to quantify T2* signal intensity, as done in
# [Martin et al. PLoS One 2018].
# Quantify average WM and GM signal between slices 2 and 12.
sct_extract_metric -i t2s.nii.gz -f t2s_wmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv
sct_extract_metric -i t2s.nii.gz -f t2s_gmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv -append 1
# Note: the flag -append enables to append a new result at the end of an already-existing csv file.



# Gray matter segmentation (Improving registration results using binary segmentation masks)
# ======================================================================================================================

# Register template->t2s (using warping field generated from template<->t2 registration)
# Tips: Here we use the WM seg for the iseg/dseg fields in order to account for both the cord and the GM shape.
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t2s.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_wm.nii.gz -d t2s.nii.gz -dseg t2s_wmseg.nii.gz -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2t2s.nii.gz -owarpinv warp_t2s2template.nii.gz -param step=1,type=seg,algo=rigid:step=2,type=seg,metric=CC,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,metric=CC,algo=syn,slicewise=1,iter=2 -qc ~/qc_singleSubj
# Warp template
sct_warp_template -d t2s.nii.gz -w warp_template2t2s.nii.gz -qc ~/qc_singleSubj

# Register another metric while reusing newly-created GM-informed warping fields
cd ../mt
# Register template->mt using `-initwarp` with t2s to account for GM segmentation
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t2.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz -d mt1.nii.gz -dseg mt1_seg.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -m mask_mt1.nii.gz -initwarp ../t2s/warp_template2t2s.nii.gz -owarp warp_template2mt.nii.gz -qc ~/qc_singleSubj
# Warp template
sct_warp_template -d mt1.nii.gz -w warp_template2mt.nii.gz -qc ~/qc_singleSubj
# Check results
fsleyes mt1.nii.gz -cm greyscale -a 100.0 label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 100.0 label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 100.0 &



# Atlas-based analysis (Extracting metrics (MTR) in gray/white matter tracts)
# ======================================================================================================================

# Extract MTR for each slice within the white matter (combined label: #51)
# Tips: To list all available labels, type: "sct_extract_metric"
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 51 -o mtr_in_wm_perslice.csv

# Extract MTR within the right and left corticospinal tract and aggregate across specific slices
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 4,5 -z 5:15 -o mtr_in_cst.csv
# You can specify the vertebral levels to extract MTR from. For example, to quantify MTR between C2 and C4 levels in the
# dorsal column (combined label: #53) using weighted average:
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 53 -vert 2:4 -vertfile label/template/PAM50_levels.nii.gz -o mtr_in_dc.csv


# Diffusion-weighted MRI
# ======================================================================================================================

cd ../dmri
# Preprocessing steps
# Compute mean dMRI from dMRI data
sct_dmri_separate_b0_and_dwi -i dmri.nii.gz -bvec bvecs.txt 
# Segment SC on mean dMRI data
# Note: This segmentation does not need to be accurate-- it is only used to create a mask around the cord
sct_deepseg spinalcord -i dmri_dwi_mean.nii.gz -qc ~/qc_singleSubj
# Create mask (for subsequent cropping)
sct_create_mask -i dmri_dwi_mean.nii.gz -p centerline,dmri_dwi_mean_seg.nii.gz -size 35mm

# Motion correction (moco)
sct_dmri_moco -i dmri.nii.gz -m mask_dmri_dwi_mean.nii.gz -bvec bvecs.txt -qc ~/qc_singleSubj -qc-seg dmri_dwi_mean_seg.nii.gz
# Check results in the QC report

# Segment SC on motion-corrected mean dwi data (check results in the QC report)
sct_deepseg spinalcord -i dmri_moco_dwi_mean.nii.gz -qc ~/qc_singleSubj

# Register template->dwi via t2 to account for cord shape (which is better defined in T2 contrast)
# Tips: Here we use the PAM50 contrast t1, which is closer to the dwi contrast (although we are not using type=im in
#       -param, so it will not make a difference here)
# Note: the flag “-initwarpinv" provides a transformation dmri->template, in case you would like to bring all your DTI
#       metrics in the PAM50 space (e.g. group averaging of FA maps)
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t1.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz -d dmri_moco_dwi_mean.nii.gz -dseg dmri_moco_dwi_mean_seg.nii.gz -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2dmri.nii.gz -owarpinv warp_dmri2template.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -qc ~/qc_singleSubj
# Warp template (so 'label/atlas' can be used to extract metrics)
sct_warp_template -d dmri_moco_dwi_mean.nii.gz -w warp_template2dmri.nii.gz -qc ~/qc_singleSubj
# Check results in the QC report

# Compute DTI metrics using dipy [1]
sct_dmri_compute_dti -i dmri_moco.nii.gz -bval bvals.txt -bvec bvecs.txt
# Tips: the flag "-method restore" estimates the tensor with robust fit (RESTORE method [2])

# Compute FA within the white matter from individual level 2 to 5
sct_extract_metric -i dti_FA.nii.gz -f label/atlas -l 51 -method map -vert 2:5 -vertfile label/template/PAM50_levels.nii.gz -perlevel 1 -o fa_in_wm.csv


# Functional MRI
# ======================================================================================================================

cd ../fmri
# Preprocessing steps
# Average all fMRI time series to make it a 3D volume (needed by the next command)
sct_maths -i fmri.nii.gz -mean t -o fmri_mean.nii.gz
# Bring t2 segmentation to fmri space (to create a mask)
sct_register_multimodal -i ../t2/t2_seg.nii.gz -d fmri_mean.nii.gz -identity 1
# Create mask at the center of the FOV
sct_create_mask -i fmri.nii.gz -p centerline,t2_seg_reg.nii.gz -size 35mm -f cylinder

# Motion correction (using mask)
sct_fmri_moco -i fmri.nii.gz -m mask_fmri.nii.gz -qc ~/qc_singleSubj -qc-seg t2_seg_reg.nii.gz

# Cord segmentation on motion-corrected averaged time series
sct_deepseg spinalcord -i fmri_moco_mean.nii.gz -qc ~/qc_singleSubj/
# TSNR before/after motion correction with QC report
sct_fmri_compute_tsnr -i fmri.nii.gz
sct_fmri_compute_tsnr -i fmri_moco.nii.gz
sct_qc -i fmri_tsnr.nii.gz -d fmri_moco_tsnr.nii.gz -s fmri_moco_mean_seg.nii.gz -p sct_fmri_compute_tsnr -qc ~/qc_singleSubj/

# Register the template to the fMRI scan.
# Note: here we don't rely on the segmentation because it is difficult to obtain one automatically. Instead, we rely on
#       ANTs_SyN superpower to find a suitable transformation between the PAM50_t2s and the fMRI scan. We don't want to
#       put too many iterations because this registration is very sensitive to the artifacts (drop out) in the image.
#       Also, we want a 3D transformation (not 2D) because we need the through-z regularization.
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t2s.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz -d fmri_moco_mean.nii.gz -dseg fmri_moco_mean_seg.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,algo=syn,metric=CC,iter=3,slicewise=1 -initwarp ../t2/warp_template2anat.nii.gz -initwarpinv ../t2/warp_anat2template.nii.gz -owarp warp_template2fmri.nii.gz -owarpinv warp_fmri2template.nii.gz -qc ~/qc_singleSubj
# Check results in the QC report

# Warp template with the spinal levels (can be found at $SCT_DIR/data/PAM50/template/)
sct_warp_template -d fmri_moco_mean.nii.gz -w warp_template2fmri.nii.gz -a 0 -qc ~/qc_singleSubj


# Other features
# ======================================================================================================================

cd ../t1
# Segment T1-weighted image (to be used in later steps)
sct_deepseg spinalcord -i t1.nii.gz -qc ~/qc_singleSubj/

# Smooth spinal cord along centerline (extracted from the segmentation)
sct_smooth_spinalcord -i t1.nii.gz -s t1_seg.nii.gz
# Tips: use flag "-sigma" to specify smoothing kernel size (in mm)

# Second-pass segmentation using the smoothed anatomical image
sct_deepseg spinalcord -i t1_smooth.nii.gz -qc ~/qc_singleSubj

# Align the spinal cord in the right-left direction using slice-wise translations.
sct_flatten_sagittal -i t1.nii.gz -s t1_seg.nii.gz
# Note: Use for visualization purposes only



# New features (SCT v6.5, December 2024)
# ======================================================================================================================

# Lesion analysis for SCI
cd ../t2_lesion
# Segment the spinal cord and intramedullary lesion using the SCIsegV2 model
# Note: t2.nii.gz contains a fake lesion for the purpose of this tutorial
sct_deepseg lesion_sci_t2 -i t2.nii.gz -qc ~/qc_singleSubj
# Note: Two files are output:
# - t2_sc_seg.nii.gz: the spinal cord segmentation
# - t2_lesion_seg.nii.gz: the lesion segmentation
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_sc_seg.nii.gz -cm red -a 70.0 t2_lesion_seg.nii.gz -cm blue-lightblue -a 70.0 &

# Compute various morphometric measures, such as number of lesions, lesion length, lesion volume, etc.
sct_analyze_lesion -m t2_lesion_seg.nii.gz -s t2_sc_seg.nii.gz -qc ~/qc_singleSubj
# Lesion analysis using PAM50 (the -f flag is used to specify the folder containing the atlas/template)
# Note: You must go through the "Register to Template" steps (labeling, registration) first
#       This is because `sct_warp_template` is required to generate the `label` folder used for `-f`
sct_warp_template -d t2.nii.gz -w ../t2/warp_template2anat.nii.gz
sct_analyze_lesion -m t2_lesion_seg.nii.gz -s t2_sc_seg.nii.gz -f label -qc ~/qc_singleSubj

# Segment the spinal cord on gradient echo EPI data
cd ../fmri/
# Crop extraneous tissue using the t2-based mask generated earlier
sct_crop_image -i fmri_moco_mean.nii.gz -m mask_fmri.nii.gz -b 0
# Segment the cord using the cropped image
sct_deepseg sc_epi -i fmri_moco_mean_crop.nii.gz -qc ~/qc_singleSubj

# Canal segmentation
cd ../t2
sct_deepseg sc_canal_t2 -i t2.nii.gz -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_canal_seg_seg.nii.gz -cm red -a 70.0 &

# Compute aSCOR (Adapted Spinal Cord Occupation Ratio)
# i.e. Spinal cord to canal ratio using the canal seg
sct_compute_ascor -i-SC t2_seg.nii.gz -i-canal t2_canal_seg.nii.gz -perlevel 1 -o ascor.csv

# Segment the spinal nerve rootlets
sct_deepseg rootlets -i t2.nii.gz -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_rootlets.nii.gz -cm subcortical -a 70.0 &

# Multiple sclerosis lesion segmentation on T2-weighted images
cd ../t2_ms/
# Segment the spinal cord (to be used as input for lesion_ms QC)
sct_deepseg spinalcord -i t2.nii.gz -qc ~/qc_singleSubj
# Segment using lesion_ms (-single-fold is recommended to speed up inference time)
sct_deepseg lesion_ms -i t2.nii.gz -qc ~/qc_singleSubj -qc-seg t2_seg.nii.gz -single-fold
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_lesion_seg.nii.gz -cm red -a 70.0 &

# Return to parent directory
cd ..
