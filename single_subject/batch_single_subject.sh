#!/bin/bash
#
# Example of commands to process multi-parametric data of the spinal cord
# For information about acquisition parameters, see: www.spinalcordmri.org/protocols
# N.B. The parameters were chosen to suit SCT's sample tutorial data. With your data,
# it is worthwhile to explore the various parameters and tweak them to your situation.
#
# tested with Spinal Cord Toolbox (v5.3.0)

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
    printf 'WARNING: FSLeyes is not installed, so the following command was skipped:\nfsleyes %s\n' "$*";
  };
fi



# ======================================================================================================================
# START OF SCRIPT
# ======================================================================================================================

# Spinal cord segmentation
# ======================================================================================================================

# Go to T2 contrast
cd data/t2
# Spinal cord segmentation
sct_propseg -i t2.nii.gz -c t2 -qc ~/qc_singleSubj
# To check the QC report, use your web browser to open the file qc_singleSubj/qc/index.html, which has been created in
# your home directory

# Go to T1 contrast
cd ../t1
# Spinal cord segmentation
sct_propseg -i t1.nii.gz -c t1 -qc ~/qc_singleSubj
# Check QC report: Go to your browser and do "refresh". Notice that the segmentation is "leaking".
# Try another algorithm based on deep-learning
sct_deepseg_sc -i t1.nii.gz -c t1 -qc ~/qc_singleSubj -ofolder deepseg
# Check QC report: Go to your browser and do "refresh". Notice that the leakage is fixed.
# Optional: Check results in FSLeyes. In red: PropSeg, in green: DeepSeg. Tips: use the right arrow key to switch
#           overlay on/off.
fsleyes t1.nii.gz -cm greyscale t1_seg.nii.gz -cm red -a 70.0 deepseg/t1_seg.nii.gz -cm green -a 70.0 &



# Vertebral labeling
# ======================================================================================================================

cd ../t2
# Vertebral labeling
sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2 -qc ~/qc_singleSubj
# Check QC report: Go to your browser and do "refresh".
# Note: Here, two files are output: t2_seg_labeled, which represents the labeled segmentation (i.e., the value
#       corresponds to the vertebral level), and t2_seg_labeled_discs, which only has a single point for each
#       inter-vertebral disc level. The convention is: Value 3 —> C2-C3 disc, Value 4 —> C3-C4 disc, etc.

# OPTIONAL: If automatic labeling did not work, you can initialize with manual identification of C2-C3 disc:
#sct_label_utils -i t2.nii.gz -create-viewer 3 -o label_c2c3.nii.gz \
#                -msg "Click at the posterior tip of C2/C3 inter-vertebral disc"
#sct_label_vertebrae -i t2.nii.gz -s t2_seg.nii.gz -c t2 -initlabel label_c2c3.nii.gz -qc ~/qc_singleSubj

# Create labels at C3 and T2 mid-vertebral levels. These labels are needed for template registration.
sct_label_utils -i t2_seg_labeled.nii.gz -vert-body 3,9 -o t2_labels_vert.nii.gz

# OPTIONAL: You might want to completely bypass sct_label_vertebrae and do the labeling manually. In that case, we
# provide a viewer to do so conveniently. In the example command below, we will create labels at the inter-vertebral
# discs C2-C3 (value=3), C3-C4 (value=4) and C4-C5 (value=5).
#sct_label_utils -i t2.nii.gz -create-viewer 3,4,5 -o labels_disc.nii.gz \
#                -msg "Place labels at the posterior tip of each inter-vertebral disc. E.g. Label 3: C2/C3, Label 4: C3/C4, etc."




# Registratering T2 data to the PAM50 template
# ======================================================================================================================

# Register t2->template.
sct_register_to_template -i t2.nii.gz -s t2_seg.nii.gz -l t2_labels_vert.nii.gz -c t2 -qc ~/qc_singleSubj
# Note: By default the PAM50 template is selected. You can also select your own template using flag -t.

# Warp template objects (T2, cord segmentation, vertebral levels, etc.). Here we use -a 0 because we don’t need the
# white matter atlas at this point.
sct_warp_template -d t2.nii.gz -w warp_template2anat.nii.gz -a 0 -qc ~/qc_singleSubj
# Note: A folder label/template/ is created, which contains template objects in the space of the subject. The file
#       info_label.txt lists all template files.

# Check results using Fsleyes. Tips: use the right arrow key to switch overlay on/off.
fsleyes t2.nii.gz -cm greyscale -a 100.0 \
        label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 \
        label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 50.0 \
        label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 50.0 &



# Computing shape metrics
# ======================================================================================================================

# Compute cross-sectional area (CSA) of spinal cord and average it across levels C3 and C4
sct_process_segmentation -i t2_seg.nii.gz -vert 3:4 -vertfile ./label/template/PAM50_levels.nii.gz -o csa_c3c4.csv
# Aggregate CSA value per level
sct_process_segmentation -i t2_seg.nii.gz -vert 3:4 -vertfile ./label/template/PAM50_levels.nii.gz -perlevel 1 -o csa_perlevel.csv
# Aggregate CSA value per slices
sct_process_segmentation -i t2_seg.nii.gz -z 30:35 -perslice 1 -o csa_perslice.csv



# Registering additional MT data to the PAM50 template
# ======================================================================================================================

# Go to mt folder
cd ../mt
# Segment cord
sct_deepseg_sc -i mt1.nii.gz -c t2 -qc ~/qc_singleSubj

# Create a close mask around the spinal cord for more accurate registration (i.e. does not account for surrounding
# tissue which could move independently from the cord)
sct_create_mask -i mt1.nii.gz -p centerline,mt1_seg.nii.gz -size 35mm -f cylinder -o mask_mt1.nii.gz

# Register template->mt1. The flag -initwarp ../t2/warp_template2anat.nii.gz initializes the registration using the
# template->t2 transformation which was previously estimated
sct_register_multimodal -i $SCT_DIR/data/PAM50/template/PAM50_t2.nii.gz -iseg $SCT_DIR/data/PAM50/template/PAM50_cord.nii.gz \
                        -d mt1.nii.gz -dseg mt1_seg.nii.gz \
                        -m mask_mt1.nii.gz -initwarp ../t2/warp_template2anat.nii.gz \
                        -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3  \
                        -owarp warp_template2mt.nii.gz -qc ~/qc_singleSubj
# Tips: Here we only use the segmentations (type=seg) to minimize the sensitivity of the registration procedure to
#       image artifacts.
# Tips: Step 1: algo=centermass to align source and destination segmentations, then Step 2: algo=bpslinesyn to adapt the
#       shape of the cord to the mt modality (in case there are distortions between the t2 and the mt scan).

# Warp template
sct_warp_template -d mt1.nii.gz -w warp_template2mt.nii.gz -a 1 -qc ~/qc_singleSubj
# Check results using Fsleyes. Tips: use the right arrow key to switch overlay on/off.
fsleyes mt1.nii.gz -cm greyscale -a 100.0 \
        label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 \
        label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 50.0 \
        label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 50.0 &



# Computing MTR
# ======================================================================================================================

# Register mt0->mt1 using z-regularized slicewise translations (algo=slicereg)
sct_register_multimodal -i mt0.nii.gz -d mt1.nii.gz -dseg mt1_seg.nii.gz -m mask_mt1.nii.gz \
                        -param step=1,type=im,algo=slicereg,metric=CC -x spline -qc ~/qc_singleSubj
# Check results using Fsleyes. Tips: use the right arrow key to switch overlay on/off.
fsleyes mt1.nii.gz mt0_reg.nii.gz &
# Compute MTR
sct_compute_mtr -mt0 mt0_reg.nii.gz -mt1 mt1.nii.gz
# Note: MTR is given in percentage.



# Gray/white matter segmentation
# ======================================================================================================================

# Go to T2*-weighted data, which has good GM/WM contrast and high in-plane resolution
cd ../t2s
# Segment gray matter (check QC report afterwards)
sct_deepseg_gm -i t2s.nii.gz -qc ~/qc_singleSubj
# Spinal cord segmentation
sct_deepseg_sc -i t2s.nii.gz -c t2s -qc ~/qc_singleSubj
# Subtract GM segmentation from cord segmentation to obtain WM segmentation
sct_maths -i t2s_seg.nii.gz -sub t2s_gmseg.nii.gz -o t2s_wmseg.nii.gz



# Improving registration results using gray/white matter segmentations
# ======================================================================================================================

# Register template->t2s (using warping field generated from template<->t2 registration)
# Tips: Here we use the WM seg for the iseg/dseg fields in order to account for both the cord and the GM shape.
sct_register_multimodal -i "${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz" \
                        -iseg "${SCT_DIR}/data/PAM50/template/PAM50_wm.nii.gz" \
                        -d t2s.nii.gz \
                        -dseg t2s_wmseg.nii.gz \
                        -initwarp ../t2/warp_template2anat.nii.gz \
                        -initwarpinv ../t2/warp_anat2template.nii.gz \
                        -owarp warp_template2t2s.nii.gz \
                        -owarpinv warp_t2s2template.nii.gz \
                        -param step=1,type=seg,algo=rigid:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 \
                        -qc ~/qc_singleSubj

cd ../mt
# Register template->mt via t2s to account for GM segmentation
sct_register_multimodal -i "${SCT_DIR}/data/PAM50/template/PAM50_t2.nii.gz" \
                        -iseg "${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz" \
                        -d mt1.nii.gz \
                        -dseg mt1_seg.nii.gz \
                        -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 \
                        -m mask_mt1.nii.gz \
                        -initwarp ../t2s/warp_template2t2s.nii.gz \
                        -owarp warp_template2mt.nii.gz \
                        -qc ~/qc_singleSubj


# Computing metrics for gray/white matter (including atlas-based tract analysis)
# ======================================================================================================================

# Metrics using WM/GM mask only (no atlas)
cd ../t2s
# Compute cross-sectional area (CSA) of the gray and white matter for all slices in the volume.
# Note: Here we use the flag -angle-corr 0, because we do not want to correct the computed CSA by the cosine of the
# angle between the cord centerline and the S-I axis: we assume that slices were acquired orthogonally to the cord.
sct_process_segmentation -i t2s_wmseg.nii.gz -o csa_wm.csv -angle-corr 0
sct_process_segmentation -i t2s_gmseg.nii.gz -o csa_gm.csv -angle-corr 0

# You can also use a single binary mask to extract signal intensity from MRI data.
# The example below will show how to use the GM and WM segmentations to quantify T2* signal intensity, as done in
# [Martin et al. PLoS One 2018].
# Quantify average WM and GM signal between slices 2 and 12.
sct_extract_metric -i t2s.nii.gz -f t2s_wmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv
sct_extract_metric -i t2s.nii.gz -f t2s_gmseg.nii.gz -method bin -z 2:12 -o t2s_value.csv -append 1
# Note: the flag -append enables to append a new result at the end of an already-existing csv file.

# Atlas-based tract analysis
cd ../mt
# In order to use the PAM50 atlas to extract/aggregate image data, the atlas must first be transformed to the MT space
sct_warp_template -d mt1.nii.gz -w warp_template2mt.nii.gz -a 1 -qc ~/qc_singleSubj
# Check results
fsleyes mt1.nii.gz -cm greyscale -a 100.0 \
        label/template/PAM50_t2.nii.gz -cm greyscale -dr 0 4000 -a 100.0 \
        label/template/PAM50_gm.nii.gz -cm red-yellow -dr 0.4 1 -a 100.0 \
        label/template/PAM50_wm.nii.gz -cm blue-lightblue -dr 0.4 1 -a 100.0 &

# Extract MTR for each slice within the white matter (combined label: #51)
# Tips: To list all available labels, type: "sct_extract_metric"
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 51 -o mtr_in_wm.csv

# Extract MTR within the right and left corticospinal tract and aggregate across specific slices
sct_extract_metric -i mtr.nii.gz -f label/atlas -method map -l 4,5 -z 5:15 -o mtr_in_cst.csv
# You can specify the vertebral levels to extract MTR from. For example, to quantify MTR between C2 and C4 levels in the
# dorsal column (combined label: #53) using weighted average:
sct_extract_metric -i mtr.nii.gz -f label/atlas -method wa -l 53 -vert 2:4 -o mtr_in_dc.csv


# Diffusion-weighted MRI
# ======================================================================================================================

cd ../dmri
# Preprocessing steps
# Compute mean dMRI from dMRI data
sct_maths -i dmri.nii.gz -mean t -o dmri_mean.nii.gz
# Segment SC on mean dMRI data
# Note: This segmentation does not need to be accurate-- it is only used to create a mask around the cord
sct_deepseg_sc -i dmri_mean.nii.gz -c dwi -qc ~/qc_singleSubj
# Create mask (for subsequent cropping)
sct_create_mask -i dmri_mean.nii.gz -p centerline,dmri_mean_seg.nii.gz -f cylinder -size 35mm

# Motion correction (moco)
sct_dmri_moco -i dmri.nii.gz -m mask_dmri_mean.nii.gz -bvec bvecs.txt

# Compute DTI metrics using dipy [1]
sct_dmri_compute_dti -i dmri_moco.nii.gz -bval bvals.txt -bvec bvecs.txt
# Tips: the flag "-method restore" estimates the tensor with robust fit (RESTORE method [2])

# Segment SC on motion-corrected mean dwi data (check results in the QC report)
sct_deepseg_sc -i dmri_moco_dwi_mean.nii.gz -c dwi -qc ~/qc_singleSubj
# Register template->dwi via t2s to account for GM segmentation
# Tips: Here we use the PAM50 contrast t1, which is closer to the dwi contrast (although we are not using type=im in
#       -param, so it will not make a difference here)
# Note: the flag “-initwarpinv" provides a transformation dmri->template, in case you would like to bring all your DTI
#       metrics in the PAM50 space (e.g. group averaging of FA maps)
sct_register_multimodal -i "${SCT_DIR}/data/PAM50/template/PAM50_t1.nii.gz" \
                        -iseg "${SCT_DIR}/data/PAM50/template/PAM50_cord.nii.gz" \
                        -d dmri_moco_dwi_mean.nii.gz \
                        -dseg dmri_moco_dwi_mean_seg.nii.gz \
                        -initwarp ../t2s/warp_template2t2s.nii.gz \
                        -initwarpinv ../t2s/warp_t2s2template.nii.gz \
                        -owarp warp_template2dmri.nii.gz \
                        -owarpinv warp_dmri2template.nii.gz \
                        -param step=1,type=seg,algo=centermass:step=2,type=seg,algo=bsplinesyn,slicewise=1,iter=3 \
                        -qc ~/qc_singleSubj

# Warp template
sct_warp_template -d dmri_moco_dwi_mean.nii.gz -w warp_template2dmri.nii.gz -qc ~/qc_singleSubj
# Check results in the QC report

# Compute FA within the white matter from individual level 2 to 5
sct_extract_metric -i dti_FA.nii.gz -f label/atlas \
                   -l 51 -method map \
                   -vert 2:5 -vertfile label/template/PAM50_levels.nii.gz -perlevel 1 \
                   -o fa_in_wm.csv



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
sct_fmri_moco -i fmri.nii.gz -m mask_fmri.nii.gz

# Register the template to the fMRI scan.
# Note: here we don't rely on the segmentation because it is difficult to obtain one automatically. Instead, we rely on
#       ANTs_SyN superpower to find a suitable transformation between the PAM50_t2s and the fMRI scan. We don't want to
#       put too many iterations because this registration is very sensitive to the artifacts (drop out) in the image.
#       Also, we want a 3D transformation (not 2D) because we need the through-z regularization.
sct_register_multimodal -i "${SCT_DIR}/data/PAM50/template/PAM50_t2s.nii.gz" \
                        -d fmri_moco_mean.nii.gz \
                        -dseg t2_seg_reg.nii.gz \
                        -param step=1,type=im,algo=syn,metric=CC,iter=5,slicewise=0 \
                        -initwarp ../t2s/warp_template2t2s.nii.gz \
                        -initwarpinv ../t2s/warp_t2s2template.nii.gz \
                        -owarp warp_template2fmri.nii.gz \
                        -owarpinv warp_fmri2template.nii.gz \
                        -qc ~/qc_singleSubj
# Check results in the QC report

# Warp template with the spinal levels (-s 1)
sct_warp_template -d fmri_moco_mean.nii.gz -w warp_template2fmri.nii.gz -s 1 -a 0 -qc ~/qc_singleSubj
# Check results
fsleyes --scene lightbox --hideCursor fmri_moco_mean.nii.gz -cm greyscale -dr 0 1000 \
                                      label/spinal_levels/spinal_level_03 -cm red \
                                      label/spinal_levels/spinal_level_04 -cm blue \
                                      label/spinal_levels/spinal_level_05 -cm green \
                                      label/spinal_levels/spinal_level_06 -cm yellow



# Other features
# ======================================================================================================================

# Smooth spinal cord along centerline (extracted from the segmentation)
cd ../t1
sct_smooth_spinalcord -i t1.nii.gz -s t1_seg.nii.gz
# Tips: use flag "-sigma" to specify smoothing kernel size (in mm)

# Align the spinal cord in the right-left direction using slice-wise translations.
sct_flatten_sagittal -i t1.nii.gz -s t1_seg.nii.gz

# Return to parent directory
cd ..
