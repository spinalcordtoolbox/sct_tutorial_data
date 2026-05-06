#!/usr/bin/env python3
"""process_csvs.py — Transform SCT output CSVs into tutorial documentation CSVs.

Usage:
    python process_csvs.py [--input-dir DIR] [--output-dir DIR]

    --input-dir  Root of the CI-downloaded CSV tree.
                 Default: ./csvs/ (relative to CWD)
    --output-dir Root of the tutorials documentation tree.
                 Default: $SCT_DIR/documentation/source/user_section/tutorials/

Instructions:

1. Run the CI for `sct_tutorial_data`.
2. Navigate to the latest runs of the CI:
    - https://github.com/spinalcordtoolbox/sct_tutorial_data/actions/workflows/run_script_and_create_release.yml
    - https://github.com/spinalcordtoolbox/sct_tutorial_data/actions/workflows/run_batch_script.yml
3. Fetch the zips containing the metric CSVs for both runs.
4. Create a folder and put both extracted zips into the folder. It should look like:
    - ./csvs/Single Subject CSV Files/... (t2, dmri, etc.)
    - ./csvs/Multi Subject CSV Files/results/... (CSA.csv, MTR_in_DC.csv)
5. Run this script, making sure to point `--input-dir` at the right directory.
6. Commit the updated CSV files (in the docs dir) to your PR.
"""

import argparse
import os
import sys
from pathlib import Path

import pandas as pd

FILENAME_ANCHOR = "sct_tutorial_data/"


def strip_filename_prefix(series: pd.Series) -> pd.Series:
    """Strip everything up to and including the last 'sct_tutorial_data/' segment."""
    def _strip(value: str) -> str:
        if not isinstance(value, str):
            return value
        idx = value.rfind(FILENAME_ANCHOR)
        return value[idx + len(FILENAME_ANCHOR):] if idx != -1 else value
    return series.map(_strip)


def vertlevel_has_data(df: pd.DataFrame) -> bool:
    """Return True if VertLevel contains at least one non-null, non-empty, non-zero value."""
    if "VertLevel" not in df.columns:
        return False
    non_null = df["VertLevel"].dropna()
    if non_null.empty:
        return False
    as_str = non_null.astype(str).str.strip()
    return any(v not in ("", "0", "nan", "None") for v in as_str)


def process(
    input_path: Path,
    output_path: Path,
    keep_cols: list[str],
    rename_cols: dict[str, str] | None = None,
    conditional_vertlevel: bool = False,
    head: int = -1,
    tail: int = -1,
) -> None:
    df = pd.read_csv(input_path)

    if conditional_vertlevel and "VertLevel" in keep_cols:
        if not vertlevel_has_data(df):
            keep_cols = [c for c in keep_cols if c != "VertLevel"]

    missing = [c for c in keep_cols if c not in df.columns]
    if missing:
        sys.exit(
            f"ERROR: Columns missing in '{input_path}':\n"
            + "\n".join(f"  {c}" for c in missing)
            + f"\nAvailable: {list(df.columns)}"
        )

    df = df[keep_cols].copy()

    if head >= 0 and tail >= 0 and len(df) > head + tail:
        sentinel = pd.DataFrame([["..."] + [float("nan")] * (len(keep_cols) - 1)],
                                columns=keep_cols)
        df = pd.concat([df.iloc[:head], sentinel, df.iloc[-tail:]], ignore_index=True)

    if "Filename" in df.columns:
        df["Filename"] = strip_filename_prefix(df["Filename"])

    if rename_cols:
        df = df.rename(columns=rename_cols)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_path, index=False)
    print(f"Written: {output_path}  ({len(df)} row(s), {len(df.columns)} column(s))")


# ---------------------------------------------------------------------------
# Per-file processing functions (one per input CSV, called by run_all)
# ---------------------------------------------------------------------------

def process_ap_ratio(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/normalizing-morphometrics-compressions"
    process(
        ci_root / "t2_compression/ap_ratio.csv",
        out / "ap_ratio.csv",
        keep_cols=["filename", "compression_level", "Slice (I->S)",
                   "diameter_AP_ratio", "diameter_AP_ratio_PAM50", "diameter_AP_ratio_PAM50_normalized"],
        rename_cols={"Slice (I->S)": "slice(I->S)"},
    )


def process_ap_ratio_norm_pam50(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/normalizing-morphometrics-compressions"
    process(
        ci_root / "t2_compression/ap_ratio_norm_PAM50.csv",
        out / "ap_ratio_norm_PAM50.csv",
        keep_cols=["filename", "compression_level", "Slice (I->S)",
                   "diameter_AP_ratio", "diameter_AP_ratio_PAM50", "diameter_AP_ratio_PAM50_normalized"],
        rename_cols={"Slice (I->S)": "slice(I->S)"},
    )


def process_csa_c3c4(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/compute-csa-and-other-shape-metrics"
    process(
        ci_root / "t2/csa_c3c4.csv",
        out / "csa_c3c4.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "MEAN(area)", "STD(area)"],
        conditional_vertlevel=True,
    )


def process_csa_perlevel(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/compute-csa-and-other-shape-metrics"
    # Primary output: cross-sectional area
    process(
        ci_root / "t2/csa_perlevel.csv",
        out / "csa_perlevel.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "MEAN(area)", "STD(area)"],
        conditional_vertlevel=True,
    )
    # Secondary outputs: angle, diameter, and other shape metrics
    process(
        ci_root / "t2/csa_perlevel.csv",
        out / "angle-ap-rl.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel",
                   "MEAN(angle_AP)", "STD(angle_AP)", "MEAN(angle_RL)", "STD(angle_RL)"],
        conditional_vertlevel=True,
    )
    process(
        ci_root / "t2/csa_perlevel.csv",
        out / "other-shape-metrics-1.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel",
                   "MEAN(diameter_AP)", "STD(diameter_AP)", "MEAN(diameter_RL)", "STD(diameter_RL)"],
        conditional_vertlevel=True,
    )
    process(
        ci_root / "t2/csa_perlevel.csv",
        out / "other-shape-metrics-2.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel",
                   "MEAN(eccentricity)", "STD(eccentricity)", "MEAN(orientation)", "STD(orientation)",
                   "MEAN(solidity)", "STD(solidity)", "SUM(length)"],
        conditional_vertlevel=True,
    )


def process_csa_perslice(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/compute-csa-and-other-shape-metrics"
    process(
        ci_root / "t2/csa_perslice.csv",
        out / "csa_perslice.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "MEAN(area)", "STD(area)"],
        conditional_vertlevel=True,
    )


def process_csa_pmj(ci_root: Path, tutorials_root: Path) -> None:
    out = tutorials_root / "shape-analysis/compute-csa-and-other-shape-metrics"
    process(
        ci_root / "t2/csa_pmj.csv",
        out / "csa_pmj.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "DistancePMJ", "MEAN(area)", "STD(area)"],
        conditional_vertlevel=True,
    )


def process_fa_in_wm(ci_root: Path, tutorials_root: Path) -> None:
    process(
        ci_root / "dmri/fa_in_wm.csv",
        tutorials_root / "diffusion-weighted-mri/fa_in_wm.csv",
        keep_cols=["Slice (I->S)", "VertLevel", "Label", "Size [vox]", "MAP()", "STD()"],
        conditional_vertlevel=True,
    )


def process_mtr_in_cst(ci_root: Path, tutorials_root: Path) -> None:
    process(
        ci_root / "mt/mtr_in_cst.csv",
        tutorials_root / "atlas-based-analysis/mtr_in_cst.csv",
        keep_cols=["Slice (I->S)", "VertLevel", "Label", "Size [vox]", "MAP()", "STD()"],
        conditional_vertlevel=True,
    )


def process_mtr_in_dc(ci_root: Path, tutorials_root: Path) -> None:
    # atlas-based-analysis output: no Filename column
    process(
        ci_root / "mt/mtr_in_dc.csv",
        tutorials_root / "atlas-based-analysis/mtr_in_dc.csv",
        keep_cols=["Slice (I->S)", "VertLevel", "Label", "Size [vox]", "MAP()", "STD()"],
        conditional_vertlevel=True,
    )


def process_mtr_in_wm(ci_root: Path, tutorials_root: Path) -> None:
    process(
        ci_root / "mt/mtr_in_wm.csv",
        tutorials_root / "atlas-based-analysis/mtr_in_wm.csv",
        keep_cols=["Slice (I->S)", "VertLevel", "Label", "Size [vox]", "MAP()", "STD()"],
        conditional_vertlevel=True,
        head=7,
        tail=2
    )


def process_t2s_value(ci_root: Path, tutorials_root: Path) -> None:
    process(
        ci_root / "t2s/t2s_value.csv",
        tutorials_root / "gray-matter-segmentation/gm-wm-metric-computation/t2s_value.csv",
        keep_cols=["Slice (I->S)", "VertLevel", "Label", "Size [vox]", "BIN()", "STD()"],
        conditional_vertlevel=True,
    )


def process_multi_subject(ci_root: Path, tutorials_root: Path) -> None:
    process(
        ci_root / "results/CSA.csv",
        tutorials_root / "analysis-pipelines-with-sct/CSA.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "MEAN(area)", "STD(area)"],
        conditional_vertlevel=True
    )
    process(
        ci_root / "results/MTR_in_DC.csv",
        tutorials_root / "analysis-pipelines-with-sct/MTR_in_DC.csv",
        keep_cols=["Filename", "Slice (I->S)", "VertLevel", "Label", "Size [vox]", "MAP()", "STD()"],
        conditional_vertlevel=True
    )


# ---------------------------------------------------------------------------
# Run-all driver
# ---------------------------------------------------------------------------

def run_all(ci_root: Path, tutorials_root: Path) -> None:
    """Process all tutorial CSVs. Each call below handles one input file."""

    # Single-subject CSV files
    ci_root_single = ci_root / "Single Subject CSV Files"
    process_ap_ratio(ci_root_single, tutorials_root)
    process_ap_ratio_norm_pam50(ci_root_single, tutorials_root)
    process_csa_c3c4(ci_root_single, tutorials_root)
    process_csa_perlevel(ci_root_single, tutorials_root)
    process_csa_perslice(ci_root_single, tutorials_root)
    process_csa_pmj(ci_root_single, tutorials_root)
    process_fa_in_wm(ci_root_single, tutorials_root)
    process_mtr_in_cst(ci_root_single, tutorials_root)
    process_mtr_in_dc(ci_root_single, tutorials_root)
    process_mtr_in_wm(ci_root_single, tutorials_root)
    process_t2s_value(ci_root_single, tutorials_root)

    # Multi-subject CSV files
    ci_root_multi = ci_root / "Multi Subject CSV Files"
    process_multi_subject(ci_root_multi, tutorials_root)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Transform SCT CI output CSVs into tutorial documentation CSVs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--input-dir",
        default=None,
        metavar="DIR",
        help="Root of the CI-downloaded CSV tree (default: './csvs/' in CWD).",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        metavar="DIR",
        help="Root of the tutorials tree (default: $SCT_DIR/documentation/source/user_section/tutorials/).",
    )
    args = parser.parse_args()

    ci_root = Path(args.input_dir) if args.input_dir else Path.cwd() / "csvs"

    if args.output_dir:
        tutorials_root = Path(args.output_dir)
    else:
        sct_dir = os.environ.get("SCT_DIR")
        if not sct_dir:
            sys.exit("ERROR: $SCT_DIR is not set. Pass --output-dir or set $SCT_DIR.")
        tutorials_root = Path(sct_dir) / "documentation/source/user_section/tutorials"

    run_all(ci_root, tutorials_root)


if __name__ == "__main__":
    main()