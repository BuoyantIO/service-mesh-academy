import os
import subprocess
from datetime import datetime

def find_readme_files():
    subdirectories = [ name for name in os.listdir(".") if os.path.isdir(name) ]

    readme_files = []
    for subdir in subdirectories:
        readme_path = os.path.join(subdir, 'README.md')
        if os.path.isfile(readme_path):
            readme_files.append(readme_path)

    return readme_files

def get_last_modified_date(file_path):
    """Get the last modified date of a file from Git"""
    try:
        # Get the last commit date for the specific file
        result = subprocess.run([
            'git', 'log', '-1', '--format=%cd', '--date=short', file_path
        ], capture_output=True, text=True, check=True)

        if result.stdout.strip():
            return result.stdout.strip()
        else:
            # If no git history, fall back to file system date
            stat = os.stat(file_path)
            return datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d')
    except (subprocess.CalledProcessError, FileNotFoundError):
        # If git command fails, fall back to file system date
        try:
            stat = os.stat(file_path)
            return datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d')
        except OSError:
            return "unknown"

def find_lines_with_prefix(file_path, prefixes):
    lines = []
    with open(file_path, 'r') as file:
        for line in file:
            if line.startswith(tuple(prefixes)):
                lines.append(line.strip())
    return lines

output = [
    "# Service Mesh Academy",
    "",
    "This repo is the home to all the scripts and configuration files that are used",
    "in the various [Service Mesh Academy](https://buoyant.io/service-mesh-academy)",
    "workshops hosted by Buoyant.",
    "",
    "Each workshop has a README.md that contains the instructions for the workshop.",
    "(To rebuild this master index, just run `make` in the root of this repo.)",
    "",
    "## Workshops",
]

workshops = []

readme_files = find_readme_files()

for readme_file in readme_files:
    sma_index = None
    sma_description = None
    title = None

    for line in open(readme_file):
        if line.startswith("# "):
            title = line[2:].strip()
            break

        if line.startswith("SMA-Index: "):
            sma_index = line[10:].strip()
        elif line.startswith("SMA-Description: "):
            sma_description = line[16:].strip()

    if sma_index and (sma_index.lower() == "skip"):
        # print(f"<!-- skip {readme_file} -->")
        continue

    # Get the last modified date from Git
    last_modified = get_last_modified_date(readme_file)

    workshops.append(f"* [**{title}**]({readme_file}) - {sma_description} *(last updated: {last_modified})*")

print("\n".join(output))
print("\n".join(sorted(workshops)))


