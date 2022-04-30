#!/bin/bash -e

scriptName="${0##*/}"

usage()
{
cat >&2 << EOF
usage: ${scriptName} options

OPTIONS:
  -h  Show this message
  -s  System name, default: system
  -n  Name of dump
  -a  Access token to Google storage

Example: ${scriptName} -n core1 -d 2018-06-05
EOF
}

trim()
{
  echo -n "$1" | xargs
}

system="system"
name=
accessToken=

while getopts hs:n:a:? option; do
  case "${option}" in
    h) usage; exit 1;;
    s) system=$(trim "$OPTARG");;
    n) name=$(trim "$OPTARG");;
    a) accessToken=$(trim "$OPTARG");;
    ?) usage; exit 1;;
  esac
done

if [[ -z "${system}" ]]; then
  usage
  exit 1
fi

if [[ -z "${name}" ]]; then
  usage
  exit 1
fi

currentPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -f "${currentPath}/env.properties" ]; then
  echo "No environment specified!"
  exit 1
fi

projectId=$(ini-parse "${currentPath}/env.properties" "yes" "${system}" "projectId")

if [ -z "${projectId}" ]; then
  echo "No project id in environment!"
  exit 1
fi

date=$(date +%Y-%m-%d)

if [[ -z "${accessToken}" ]]; then
  echo "Please specify access token to Google storage, followed by [ENTER]:"
  read -r accessToken
fi

dumpPath="${currentPath}/dumps/"

mkdir -p "${dumpPath}"

file="${dumpPath}/solr-${name}-${date}.tar.gz"
objectFile="${projectId}-${name}.tar.gz"

fileUrl="https://www.googleapis.com/download/storage/v1/b/tofex_vm_solr/o/${objectFile}?alt=media"

echo "Downloading file: ${fileUrl}"

fileFound=$(curl -s --head -H "Authorization: Bearer ${accessToken}" "${fileUrl}" | head -n 1 | grep -c "HTTP/2 2" || true)

if [[ "${fileFound}" == 0 ]]; then
  fileFound=$(curl -s --head -H "Authorization: Bearer ${accessToken}" "${fileUrl}" | head -n 1 | grep -c "HTTP/1.1 2" || true)
fi

if [[ "${fileFound}" == 0 ]]; then
  echo "Dump file not found or accessible!"
  exit 1
fi

curl -X GET -H "Authorization: Bearer ${accessToken}" -o "${file}" "${fileUrl}"
