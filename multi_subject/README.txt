
Spinal cord analysis pipeline for the SCT course.


GETTING STARTED
===============

- Update permission by running: chmod 775 process_data.sh
- Run:
  ```
  sct_run_batch -script process_data.sh -path-data data/ -path-output output -jobs 3
  ```
- Check QC report (under output/qc/index.html) and output/results/


DATA
====

The data are from the Spinal Cord MRI Public Database (site: unf).

The file structure follows the BIDS convention:

data
 |- subj-01
 |- subj-03
 |- subj-05
    |- anat
       |- sub-05_T2w.nii.gz
       |- sub-05_acq-MTon_MTS.nii.gz
       |- sub-05_acq-MToff_MTS.nii.gz


SCT VERSION
===========

This pipeline has been tested on 5.4, which can be downloaded here:
https://github.com/spinalcordtoolbox/spinalcordtoolbox/releases

Also see SCT installation instructions:
https://spinalcordtoolbox.com/user_section/installation.html
