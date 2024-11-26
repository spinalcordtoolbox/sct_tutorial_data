#!/bin/bash
#
# Example of commands to process multi-parametric data of the spinal cord
# For information about acquisition parameters, see: www.spinalcordmri.org/protocols
# N.B. The parameters were chosen to suit SCT's sample tutorial data. With your data,
# it is worthwhile to explore the various parameters and tweak them to your situation.
#
# tested with Spinal Cord Toolbox (v6.1.0)

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

# Go to T2 contrast
cd data/t2
# Spinal cord segmentation (using new 2024 method)
sct_deepseg -task seg_sc_contrast_agnostic -i t2.nii.gz -qc ~/qc_singleSubj
# You can also choose your own output filename using the “-o” argument
# sct_deepseg -task seg_sc_contrast_agnostic -i t2.nii.gz -o t2_seg_test.nii.gz

# To check the QC report, use your web browser to open the file qc_singleSubj/qc/index.html, which has been created in
# your home directory

# View the rest of the `sct_deepseg` tasks
sct_deepseg -h
# See also: https://spinalcordtoolbox.com/stable/user_section/command-line/sct_deepseg.html



# Vertebral labeling
# ======================================================================================================================

# Vertebral labeling
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2 -qc ~/qc_singleSubj
# Check QC report: Go to your browser and do "refresh".
# Note: Here, two files are output: t2_seg_labeled, which represents the labeled segmentation (i.e., the value
#       corresponds to the vertebral level), and t2_seg_labeled_discs, which only has a single point for each
#       inter-vertebral disc level. The convention is: Value 3 —> C2-C3 disc, Value 4 —> C3-C4 disc, etc.

# OPTIONAL: If automatic labeling did not work, you can initialize with manual identification of C2-C3 disc:
#sct_label_utils -i t2.nii.gz -create-viewer 3 -o label_c2c3.nii.gz -msg "Click at the posterior tip of C2/C3 inter-vertebral disc"
#sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2 -initlabel label_c2c3.nii.gz -qc ~/qc_singleSubj



# Computing shape metrics
# ======================================================================================================================

# Compute cross-sectional area (CSA) of spinal cord and average it across levels C3 and C4
sct_process_segmentation -i t2_seg.nii.gz -vert 3:4 -vertfile t2_seg_labeled.nii.gz -o csa_c3c4.csv
# Aggregate CSA value per level
sct_process_segmentation -i t2_seg.nii.gz -vert 3:4 -vertfile t2_seg_labeled.nii.gz -perlevel 1 -o csa_perlevel.csv
# Aggregate CSA value per slices
sct_process_segmentation -i t2_seg.nii.gz -z 30:35 -perslice 1 -o csa_perslice.csv

# A drawback of vertebral level-based CSA is that it doesn’t consider neck flexion and extension.
# To overcome this limitation, the CSA can instead be computed using the distance to a reference point.
# Here, we use the Pontomedullary Junction (PMJ), since the distance from the PMJ along the centerline
# of the spinal cord will vary depending on the position of the neck.
sct_detect_pmj -i t2.nii.gz -c t2 -qc ~/qc_singleSubj
# Check the QC to make sure PMJ was properly detected, then compute CSA using the distance from the PMJ:
sct_process_segmentation -i t2_seg.nii.gz -pmj t2_pmj.nii.gz -pmj-distance 64 -pmj-extent 30 -o csa_pmj.csv -qc ~/qc_singleSubj -qc-image t2.nii.gz

# The above commands will output the metrics in the subject space (with the original image's slice numbers)
# However, you can get the corresponding slice number in the PAM50 space by using the flag `-normalize-PAM50 1`
sct_process_segmentation -i t2_seg.nii.gz -vertfile t2_seg_labeled.nii.gz -perslice 1 -normalize-PAM50 1 -o csa_PAM50.csv



# Quantifying spinal cord compression (MSCC) and normalize against database of healthy controls
# ======================================================================================================================
cd ../t2_compression
# Segment the spinal cord of the compressed spine
sct_deepseg -task seg_sc_contrast_agnostic -i t2_compressed.nii.gz -qc ~/qc_singleSubj
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



# Lesion analysis
# ======================================================================================================================
cd ../t2_lesion
# Segment the spinal cord and intramedullary lesion using the SCIsegV2 model
# Note: t2.nii.gz contains a fake lesion for the purpose of this tutorial
sct_deepseg -i t2.nii.gz -task seg_sc_lesion_t2w_sci -qc ~/qc_singleSubj
# Note: Two files are output:
# - t2_sc_seg.nii.gz: the spinal cord segmentation
# - t2_lesion_seg.nii.gz: the lesion segmentation

# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_sc_seg.nii.gz -cm red -a 70.0 t2_lesion_seg.nii.gz -cm blue-lightblue -a 70.0 &

# Compute various morphometric measures, such as number of lesions, lesion length, lesion volume, etc.
sct_analyze_lesion -m t2_lesion_seg.nii.gz -s t2_sc_seg.nii.gz -qc ~/qc_singleSubj



# Rootlets segmentation
# ======================================================================================================================
cd ../t2
# Segment the spinal nerve rootlets
sct_deepseg -i t2.nii.gz -task seg_spinal_rootlets_t2w -qc ~/qc_singleSubj

# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_seg.nii.gz -cm subcortical -a 70.0 &



# Registering T2 data to the PAM50 template
# ======================================================================================================================
cd ../t2

# Create labels at C3 and T2 mid-vertebral levels. These labels are needed for template registration.
sct_label_utils -i t2_seg_labeled.nii.gz -vert-body 3,9 -o t2_labels_vert.nii.gz
# Generate a QC report to visualize the two selected labels on the anatomical image
sct_qc -i t2.nii.gz -s t2_labels_vert.nii.gz -p sct_label_utils -qc ~/qc_singleSubj

# OPTIONAL: You might want to completely bypass sct_label_vertebrae and do the labeling manually. In that case, we
# provide a viewer to do so conveniently. In the example command below, we will create labels at the inter-vertebral
# discs C2-C3 (value=3), C3-C4 (value=4) and C4-C5 (value=5).
#sct_label_utils -i t2.nii.gz -create-viewer 3,4,5 -o labels_disc.nii.gz -msg "Place labels at the posterior tip of each inter-vertebral disc. E.g. Label 3: C2/C3, Label 4: C3/C4, etc."

# Register t2->template.
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -l t2_labels_vert.nii.gz -c t2 -qc ~/qc_singleSubj
# Note: By default the PAM50 template is selected. You can also select your own template using flag -t.

# Register t2->template with modified parameters (advanced usage of `-param`)
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -l t2_labels_vert.nii.gz -qc ~/qc_singleSubj -ofolder advanced_param -c t2 -param step=1,type=seg,algo=rigid:step=2,type=seg,metric=CC,algo=bsplinesyn,slicewise=1,iter=3:step=3,type=im,metric=CC,algo=syn,slicewise=1,iter=2

# Register t2->template with large FOV (e.g. C2-L1) using `-ldisc` option
# sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -ldisc t2_seg_labeled_discs.nii.gz -c t2

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



# Registering additional MT data to the PAM50 template
# ======================================================================================================================

# Go to mt folder
cd ../mt
# Segment cord
sct_deepseg -task seg_sc_contrast_agnostic -i mt1.nii.gz -qc ~/qc_singleSubj

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



# Computing MTR using MT0/MT1 coregistration
# ======================================================================================================================

# Register mt0->mt1 using z-regularized slicewise translations (algo=slicereg)
# Note: Segmentation and mask can be re-used from "MT registration" section
sct_register_multimodal -i mt0.nii.gz -d mt1.nii.gz -dseg mt1_seg.nii.gz -m mask_mt1.nii.gz -param step=1,type=im,algo=slicereg,metric=CC -x spline -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes mt1.nii.gz mt0_reg.nii.gz &
# Compute MTR
sct_compute_mtr -mt0 mt0_reg.nii.gz -mt1 mt1.nii.gz
# Note: MTR is given in percentage.



# Registering lumbar data to the PAM50 template
# ======================================================================================================================
cd ../t2_lumbar

# Use lumbar-specific `sct_deepseg` model to segment the spinal cord
sct_deepseg -i t2_lumbar.nii.gz -task seg_lumbar_sc_t2w

# Generate labels for the 2 spinal cord landmarks: cauda equinea ('99') and T9-T10 disc ('17')
# Note: Normally this would be done manually using fsleyes' "Edit mode -> Create mask" functionality. (Uncomment below)
#
# fsleyes t2.nii.gz &
#
# However, since this is an automated script with example data, we will place the labels at known locations for the
# sake of reproducing the results in the tutorial.
sct_label_utils -i t2_lumbar.nii.gz -create 22,77,187,17:27,79,80,60 -o t2_lumbar_labels.nii.gz

# Register the image to the template using segmentation and labels
sct_register_to_template -i t2_lumbar.nii.gz \
                         -s t2_lumbar_seg.nii.gz \
                         -ldisc t2_lumbar_labels.nii.gz \
                         -c t2 -qc qc \
                         -param step=1,type=seg,algo=centermassrot:step=2,type=seg,algo=bsplinesyn,metric=MeanSquares,iter=3,slicewise=0:step=3,type=im,algo=syn,metric=CC,iter=3,slicewise=0



# Gray/white matter: Segmentation
# ======================================================================================================================

# Go to T2*-weighted data, which has good GM/WM contrast and high in-plane resolution
cd ../t2s
# Segment gray matter (check QC report afterwards)
sct_deepseg_gm -i t2s.nii.gz -qc ~/qc_singleSubj
# Spinal cord segmentation
sct_deepseg -task seg_sc_contrast_agnostic -i t2s.nii.gz -qc ~/qc_singleSubj
# Subtract GM segmentation from cord segmentation to obtain WM segmentation
sct_maths -i t2s_seg.nii.gz -sub t2s_gmseg.nii.gz -o t2s_wmseg.nii.gz



# Gray/white matter: Computing metrics using binary segmentation masks
# ======================================================================================================================

# Compute cross-sectional area (CSA) of the gray and white matter for all slices in the volume.
# Note: Here we use the flag -angle-corr 0, because we do not want to correct the computed CSA by the cosine of the
# angle between the cord centerline and the S-I axis: we assume that slices were acquired orthogonally to the cord.
sct_process_segmentation -i t2s_wmseg.nii.gz -o csa_wm.csv -perslice 1 -angle-corr 0
sct_process_segmentation -i t2s_gmseg.nii.gz -o csa_gm.csv -perslice 1 -angle-corr 0

# You can also use the binary masks to extract signal intensity from MRI data.
# The example below will show how to use the GM and WM segmentations to quantify T2* signal intensity, as done in
# [Martin et al. PLoS One 2018].
# Quantify average WM and GM signal between slices 2 and 12.
sct_extract_metric -i t2s.nii.gz -f t2s_wmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv
sct_extract_metric -i t2s.nii.gz -f t2s_gmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv -append 1
# Note: the flag -append enables to append a new result at the end of an already-existing csv file.



# Gray/white matter: Improving registration results using binary segmentation masks
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
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 51 -o mtr_in_wm.csv

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
sct_deepseg -task seg_sc_contrast_agnostic -i dmri_dwi_mean.nii.gz -qc ~/qc_singleSubj
# Create mask (for subsequent cropping)
sct_create_mask -i dmri_dwi_mean.nii.gz -p centerline,dmri_dwi_mean_seg.nii.gz -f cylinder -size 35mm

# Motion correction (moco)
sct_dmri_moco -i dmri.nii.gz -m mask_dmri_dwi_mean.nii.gz -bvec bvecs.txt -qc ~/qc_singleSubj -qc-seg dmri_dwi_mean_seg.nii.gz
# Check results in the QC report

# Segment SC on motion-corrected mean dwi data (check results in the QC report)
sct_deepseg -task seg_sc_contrast_agnostic -i dmri_moco_dwi_mean.nii.gz -qc ~/qc_singleSubj

# Register template->dwi via t2s to account for GM segmentation
# Tips: Here we use the PAM50 contrast t1, which is closer to the dwi contrast (although we are not using type=im in
#       -param, so it will not make a difference here)
# Note: the flag “-initwarpinv" provides a transformation dmri->template, in case you would like to bring all your DTI
#       metrics in the PAM50 space (e.g. group averaging of FA maps)
sct_register_multimodal -i "${SCT_DIR}"/data/PAM50/template/PAM50_t1.nii.gz -iseg "${SCT_DIR}"/data/PAM50/template/PAM50_cord.nii.gz -d dmri_moco_dwi_mean.nii.gz -dseg dmri_moco_dwi_mean_seg.nii.gz -initwarp ../t2s/warp_template2t2s.nii.gz -initwarpinv ../t2s/warp_t2s2template.nii.gz -owarp warp_template2dmri.nii.gz -owarpinv warp_dmri2template.nii.gz -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 -qc ~/qc_singleSubj
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

# Register the template to the fMRI scan.
# Note: here we don't rely on the segmentation because it is difficult to obtain one automatically. Instead, we rely on
#       ANTs_SyN superpower to find a suitable transformation between the PAM50_t2s and the fMRI scan. We don't want to
#       put too many iterations because this registration is very sensitive to the artifacts (drop out) in the image.
#       Also, we want a 3D transformation (not 2D) because we need the through-z regularization.
sct_register_multimodal -i "${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz" -d fmri_moco_mean.nii.gz -dseg t2_seg_reg.nii.gz -param step=1,type=im,algo=syn,metric=CC,iter=5,slicewise=0 -initwarp ../t2s/warp_template2t2s.nii.gz -initwarpinv ../t2s/warp_t2s2template.nii.gz -owarp warp_template2fmri.nii.gz -owarpinv warp_fmri2template.nii.gz -qc ~/qc_singleSubj
# Check results in the QC report

# Warp template with the spinal levels (can be found at $SCT_DIR/data/PAM50/template/)
sct_warp_template -d fmri_moco_mean.nii.gz -w warp_template2fmri.nii.gz -a 0 -qc ~/qc_singleSubj


# Other features
# ======================================================================================================================

cd ../t1
# Segment T1-weighted image (to be used in later steps)
sct_deepseg -task seg_sc_contrast_agnostic -i t1.nii.gz

# Smooth spinal cord along centerline (extracted from the segmentation)
sct_smooth_spinalcord -i t1.nii.gz -s t1_seg.nii.gz
# Tips: use flag "-sigma" to specify smoothing kernel size (in mm)

# Align the spinal cord in the right-left direction using slice-wise translations.
sct_flatten_sagittal -i t1.nii.gz -s t1_seg.nii.gz
# Note: Use for visualization purposes only



# New features (SCT v6.5, December 2024)
# ======================================================================================================================

# Lesion analysis
cd ../t2_lesion
# Segment the spinal cord and intramedullary lesion using the SCIsegV2 model
# Note: t2.nii.gz contains a fake lesion for the purpose of this tutorial
sct_deepseg -i t2.nii.gz -task seg_sc_lesion_t2w_sci -qc ~/qc_singleSubj
# Note: Two files are output:
# - t2_sc_seg.nii.gz: the spinal cord segmentation
# - t2_lesion_seg.nii.gz: the lesion segmentation
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_sc_seg.nii.gz -cm red -a 70.0 t2_lesion_seg.nii.gz -cm blue-lightblue -a 70.0 &
# Compute various morphometric measures, such as number of lesions, lesion length, lesion volume, etc.
sct_analyze_lesion -m t2_lesion_seg.nii.gz -s t2_sc_seg.nii.gz -qc ~/qc_singleSubj
# Lesion analysis using PAM50 (the -f flag is used to specify the folder containing the atlas/template)
sct_analyze_lesion -m t2_lesion_seg.nii.gz -s t2_sc_seg.nii.gz -f label_T2w -qc ~/qc_singleSubj

# Rootlets segmentation
cd ../t2
# Segment the spinal nerve rootlets
sct_deepseg -i t2.nii.gz -task seg_spinal_rootlets_t2w -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_seg.nii.gz -cm subcortical -a 70.0 &

# Full spinal segmentation (Vertebrae, Intervertebral discs, Spinal cord and Spinal canal)
# Segment using totalspineseg
sct_deepseg -i t2.nii.gz -task totalspineseg -qc ~/qc_singleSubj
# Check results using FSLeyes
fsleyes t2.nii.gz -cm greyscale t2_step1_canal.nii.gz -cm YlOrRd -a 70.0 t2_step1_cord.nii.gz -cm YlOrRd -a 70.0 t2_step1_levels.nii.gz -cm subcortical -a 70.0 t2_step1_output.nii.gz -cm subcortical -a 70.0 t2_step2_output.nii.gz -cm subcortical -a 70.0 &
# Return to parent directory
cd ..
