#!/usr/bin/env bash
set -euo pipefail

runtime_root="${RUNNER_TEMP}/nativecode-python"
archive="${runtime_root}/Python-3.13-iOS-support.b14.tar.gz"
framework_destination="${GITHUB_WORKSPACE}/NativeCode/Python.xcframework"
project_file="${GITHUB_WORKSPACE}/NativeCode.xcodeproj/project.pbxproj"
runtime_url="https://github.com/beeware/Python-Apple-support/releases/download/3.13-b14/Python-3.13-iOS-support.b14.tar.gz"
runtime_sha256="8b5cb76ef8d8a2946052479358eeec9d54b4496cb60920e175ec1489b5cf7963"

mkdir -p "${runtime_root}"
curl --fail --location --retry 3 --output "${archive}" "${runtime_url}"
echo "${runtime_sha256}  ${archive}" | shasum -a 256 -c -
tar -xzf "${archive}" -C "${runtime_root}"

framework_source="$(find "${runtime_root}" -type d -name 'Python.xcframework' -print -quit)"
if [[ -z "${framework_source}" ]]; then
    echo "Python.xcframework was not found in the support archive." >&2
    exit 1
fi

rm -rf "${framework_destination}"
ditto "${framework_source}" "${framework_destination}"

python3 - "${project_file}" <<'PY'
from pathlib import Path
import sys

project_path = Path(sys.argv[1])
project = project_path.read_text()

build_file = "\t\tA10000000000000000000008 /* Python.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = B10000000000000000000010 /* Python.xcframework */; };\n\t\tA10000000000000000000009 /* Python.xcframework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = B10000000000000000000010 /* Python.xcframework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };\n"
project = project.replace(
    "\t\tA10000000000000000000007 /* PythonRuntime.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000000000000000000009 /* PythonRuntime.swift */; };\n",
    "\t\tA10000000000000000000007 /* PythonRuntime.swift in Sources */ = {isa = PBXBuildFile; fileRef = B10000000000000000000009 /* PythonRuntime.swift */; };\n" + build_file,
)

file_reference = "\t\tB10000000000000000000010 /* Python.xcframework */ = {isa = PBXFileReference; explicitFileType = wrapper.xcframework; path = Python.xcframework; sourceTree = \"<group>\"; };\n"
project = project.replace(
    "\t\tB10000000000000000000009 /* PythonRuntime.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PythonRuntime.swift; sourceTree = \"<group>\"; };\n",
    "\t\tB10000000000000000000009 /* PythonRuntime.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PythonRuntime.swift; sourceTree = \"<group>\"; };\n" + file_reference,
)

project = project.replace(
    "\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXFrameworksBuildPhase section */",
    "\t\t\tfiles = (\n\t\t\t\tA10000000000000000000008 /* Python.xcframework in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXFrameworksBuildPhase section */",
    1,
)

project = project.replace(
    "\t\t\t\tB10000000000000000000009 /* PythonRuntime.swift */,\n",
    "\t\t\t\tB10000000000000000000009 /* PythonRuntime.swift */,\n\t\t\t\tB10000000000000000000010 /* Python.xcframework */,\n",
    1,
)

project = project.replace(
    "\t\t\t\tC10000000000000000000003 /* Resources */,\n",
    "\t\t\t\tC10000000000000000000003 /* Resources */,\n\t\t\t\tC10000000000000000000004 /* Embed Frameworks */,\n",
    1,
)

copy_phase = """\t\tC10000000000000000000004 /* Embed Frameworks */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = \"\";
\t\t\tdstSubfolderSpec = 10;
\t\t\tfiles = (
\t\t\t\tA10000000000000000000009 /* Python.xcframework in Embed Frameworks */,
\t\t\t);
\t\t\tname = \"Embed Frameworks\";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
"""
project = project.replace(
    "/* End PBXResourcesBuildPhase section */\n",
    "/* End PBXResourcesBuildPhase section */\n\n/* Begin PBXCopyFilesBuildPhase section */\n" + copy_phase + "/* End PBXCopyFilesBuildPhase section */\n",
    1,
)

project_path.write_text(project)
PY

echo "Embedded Python runtime prepared from ${runtime_url}"
