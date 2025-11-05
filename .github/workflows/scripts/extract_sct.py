import argparse
from pathlib import Path


def extract_sct_commands(paths, output=None):
    results = []

    for path in paths:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.lstrip()
                if (stripped.startswith("sct_") and
                        len(stripped.split(" ")) > 1):
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
