
Spinal cord analysis pipeline for the SCT course.


GETTING STARTED
===============

- Optional: install GNU parallel
- Update permission by running: chmod 775 process_data.sh
- Run: sct_run_batch parameters.sh process_data.sh
- Check QC report (under results/qc/index.html) and results/


DATA
====

The data are from the Spinal Cord MRI Public Database (site: unf).

The file structure follows the BIDS convention:

data
 |- subj-01
 |- subj-03
 |- subj-04
    |- anat
       |- sub-04_T2w.nii.gz
       |- sub-04_acq-MTon_MTS.nii.gz
       |- sub-04_acq-MToff_MTS.nii.gz


SCT VERSION
===========

This pipeline has been tested on v4.2.1, which can be downloaded here:
https://github.com/neuropoly/spinalcordtoolbox/releases

