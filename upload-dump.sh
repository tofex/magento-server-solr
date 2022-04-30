#!/bin/bash -e

scriptName="${0##*/}"

usage()
{
cat >&2 << EOF
usage: ${scriptName} options

OPTIONS:
  -h  Show this message
  -d  Date of the file
  -n  Name of dump

Example: ${scriptName} -n core1 -d 2018-06-05
EOF
}

trim()
{
  echo -n "$1" | xargs
}

date=
name=

while getopts hd:n:? option; do
  case "${option}" in
    h) usage; exit 1;;
    d) date=$(trim "$OPTARG");;
    n) name=$(trim "$OPTARG");;
    ?) usage; exit 1;;
  esac
done

if [ -z "${date}" ]; then
  usage
  exit 1
fi

if [ -z "${name}" ]; then
  usage
  exit 1
fi

currentPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -f "${currentPath}/../env.properties" ]; then
  echo "No environment specified!"
  exit 1
fi

projectId=$(ini-parse "${currentPath}/../env.properties" "yes" "system" "projectId")

if [ -z "${projectId}" ]; then
  echo "No project id in environment!"
  exit 1
fi

file="${currentPath}/dumps/solr-${name}-${date}.tar.gz"
objectFile="${projectId}-${name}.tar.gz"

if [ ! -f "${file}" ]; then
  echo "Requested upload file: ${file} does not exist!"
  exit 1
fi

curl=$(which curl)
if [ -z "${curl}" ]; then
  echo "Curl is not available!"
  exit 1
fi

echo "Please specify access token to Google storage, followed by [ENTER]:"
read -r accessToken

curl -X POST \
  -T "${file}" \
  -H "Authorization: Bearer ${accessToken}" \
  -H "Content-Type: application/x-gzip" \
  "https://www.googleapis.com/upload/storage/v1/b/tofex_vm_solr/o?uploadType=media&name=${objectFile}"
