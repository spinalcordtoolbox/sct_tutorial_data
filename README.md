# `sct_tutorial_data`

This dataset contains image files required for the **[Spinal Cord Toolbox tutorials](https://spinalcordtoolbox.com/en/latest/tutorials/tutorials.html)**. It also contains two scripts with all of the tutorial commands, to demonstrate how commands can be linked together to form a pipeline.

## Using this dataset

There are three ways to use this dataset:

1. Download the entire `sct_tutorial_data` dataset ([Releases](https://github.com/spinalcordtoolbox/sct_tutorial_data/releases/latest) -> "[Source code (.zip)](https://github.com/spinalcordtoolbox/sct_tutorial_data/archive/refs/heads/master.zip)"), then follow along with each tutorial in the documentation from start to finish. (The tutorials link together.)
2. Download the entire dataset, but use the included batch scripts ([`batch_single_subject.sh`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/single_subject/batch_single_subject.sh) and [`process_data.sh`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/multi_subject/process_data.sh)) to execute all of the commands together as a pipeline.
3. Download a single dataset for a specific tutorial ([Releases](https://github.com/spinalcordtoolbox/sct_tutorial_data/releases/latest) -> e.g. "[`data_spinalcord-segmentation.zip`](https://github.com/spinalcordtoolbox/sct_tutorial_data/releases/latest/download/data_spinalcord-segmentation.zip)"), and complete just that tutorial.

## Making changes to this dataset

If you've written or modified a tutorial for SCT, and your tutorial relies on certain files, updating this dataset requires 4 things:

1. Update the batch scripts ([`batch_single_subject.sh`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/single_subject/batch_single_subject.sh) and [`process_data.sh`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/multi_subject/process_data.sh)) with any new or modified commands.
2. Update the file [`tutorial-datasets.csv`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/tutorial-datasets.csv) for your tutorial.
    * All of the files you specify will be automatically packaged into a `.zip` download. You can then link to this download at the start of your tutorial.
    * Be sure to specify each file that needs to be present in order to complete your tutorial.
    * Try to re-use the intermediate files generated by earlier tutorial commands. (If you can't, you may commit new files to this repo.)
3. Create a new release by clicking "Run workflow" on [this GitHub Actions page](https://github.com/spinalcordtoolbox/sct_tutorial_data/actions/workflows/create_release.yml).
    * First, the workflow executes the [`batch_single_subject.sh`](https://github.com/spinalcordtoolbox/sct_tutorial_data/blob/master/single_subject/batch_single_subject.sh) script to generate all of the necessary files.
    * Then, it packages up sets of data files into `.zip` downloads. 
    * Finally, it creates a new release with the tutorial-specific `.zip` files attached.
4. In the SCT pull request for your tutorial changes, go to the [`conf.py`](https://github.com/spinalcordtoolbox/spinalcordtoolbox/blob/master/documentation/source/conf.py) file and update `extlinks` to point to your new release tag.
    * **Note:** The reason we don't use an automatically updating "latest" link is to prevent any future changes from silently breaking old documentation pages.
