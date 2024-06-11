import os

def find_readme_files():
    subdirectories = [ name for name in os.listdir(".") if os.path.isdir(name) ]

    readme_files = []
    for subdir in subdirectories:
        readme_path = os.path.join(subdir, 'README.md')
        if os.path.isfile(readme_path):
            readme_files.append(readme_path)

    return readme_files

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
    "workshops hosted by Buoyant",
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

    workshops.append(f"* [**{title}**]({readme_file}) - {sma_description}")

print("\n".join(output))
print("\n".join(sorted(workshops)))


