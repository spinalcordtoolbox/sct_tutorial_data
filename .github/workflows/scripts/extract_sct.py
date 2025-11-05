import argparse
from pathlib import Path


def extract_sct_commands(paths, output=None):
    results = []

    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.lstrip()
                # sct commands must have command + arg + value (3)
                # this excludes slide subtitles like "sct_slide ..."
                # also exclude lines with <> which are likely placeholders
                if (stripped.startswith("sct_")
                        and len(stripped.split(" ")) >= 3
                        and not ("<" in stripped and ">" in stripped)):
                    results.append(stripped.rstrip())

    if output:
        Path(output).write_text("\n".join(results), encoding="utf-8")
    else:
        print("\n".join(results))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract SCT commands "
                                                 "from TXT files.")
    parser.add_argument("files", nargs="+", help="Input text files")
    parser.add_argument("-o", "--output", help="Optional output file")
    args = parser.parse_args()

    extract_sct_commands(args.files, args.output)
