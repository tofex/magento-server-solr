#!/bin/bash -e

scriptName="${0##*/}"

usage()
{
cat >&2 << EOF
usage: ${scriptName} options

OPTIONS:
  -h  Show this message
  -u  Upload file to Tofex server
  -r  Remove after upload

Example: ${scriptName} -u
EOF
}

trim()
{
  echo -n "$1" | xargs
}

upload=0
remove=0

while getopts hur? option; do
  case ${option} in
    h) usage; exit 1;;
    u) upload=1;;
    r) remove=1;;
    ?) usage; exit 1;;
  esac
done

currentPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "${currentPath}/../env.properties" ]]; then
  echo "No environment specified!"
  exit 1
fi

serverList=( $(ini-parse "${currentPath}/../env.properties" "yes" "system" "server") )
if [[ "${#serverList[@]}" -eq 0 ]]; then
  echo "No servers specified!"
  exit 1
fi

solrCoreList=( $(ini-parse "${currentPath}/../env.properties" "yes" "system" "solr_core") )
if [[ "${#solrCoreList[@]}" -eq 0 ]]; then
  echo "No Solr cores specified!"
  exit 1
fi

cd "${currentPath}"

dumpPath="${currentPath}/dumps"
date=$(date +%Y-%m-%d)

for server in "${serverList[@]}"; do
  solr=$(ini-parse "${currentPath}/../env.properties" "no" "${server}" "solr")

  if [[ -n "${solr}" ]]; then
    type=$(ini-parse "${currentPath}/../env.properties" "yes" "${server}" "type")

    if [[ "${type}" == "local" ]]; then
      echo "Dumping Solr on local server: ${server}"

      for solrCoreId in "${solrCoreList[@]}"; do
        echo "Dumping Solr core: ${solrCoreId}"
        name=$(ini-parse "${currentPath}/../env.properties" "yes" "${solrCoreId}" "name")
        instanceDirectory=$(ini-parse "${currentPath}/../env.properties" "yes" "${solrCoreId}" "instanceDirectory")
        dataDirectory=$(ini-parse "${currentPath}/../env.properties" "yes" "${solrCoreId}" "dataDirectory")

        rm -rf /tmp/solr/
        mkdir -p /tmp/solr/

        echo "Syncing files from path: ${instanceDirectory} to path: /tmp/solr/instance"
        rsync --recursive --checksum --executability --no-owner --no-group --delete --force --verbose --exclude '/data' --exclude '/core.properties' --quiet "${instanceDirectory}/" /tmp/solr/instance/

        echo "Syncing files from path: ${instanceDirectory}/${dataDirectory} to path: /tmp/solr/data"
        rsync --recursive --checksum --executability --no-owner --no-group --delete --force --verbose --quiet "${instanceDirectory}/${dataDirectory}/" /tmp/solr/data/

        dumpFile="${dumpPath}/solr-${name}-${date}.tar.gz"
        rm -rf "${dumpFile}"

        cd /tmp/solr/
        echo "Creating archive at: ${dumpFile}"
        tar -zcf "${dumpFile}" .

        if [[ "${upload}" == 1 ]]; then
          echo "Uploading created archive"
          "${currentPath}/upload-dump.sh" -n "${name}" -d "${date}"

          if [[ "${remove}" == 1 ]]; then
            echo "Removing created archive at: ${dumpFile}"
            rm -rf "${dumpFile}"
          fi
        fi

        cd "${currentPath}"
      done
    fi
  fi
done
