#!/bin/bash -e

scriptName="${0##*/}"

usage()
{
cat >&2 << EOF
usage: ${scriptName} options

OPTIONS:
  -h  Show this message
  -s  System name, default: system
  -d  Download file from Google storage
  -a  Access token to Google storage
  -c  Solr core id
  -e  Remote Solr core name
  -f  Use this file, when not downloading from storage (optional)
  -r  Remove after import, default: no

Example: ${scriptName}
EOF
}

trim()
{
  echo -n "$1" | xargs
}

system=
download=0
accessToken=
coreId=
remoteCoreName=
dumpFile=
remove=0

while getopts hs:da:c:e:f:r? option; do
  case "${option}" in
    h) usage; exit 1;;
    s) system=$(trim "$OPTARG");;
    d) download=1;;
    a) accessToken=$(trim "$OPTARG");;
    c) coreId=$(trim "$OPTARG");;
    e) remoteCoreName=$(trim "$OPTARG");;
    f) dumpFile=$(trim "$OPTARG");;
    r) remove=1;;
    ?) usage; exit 1;;
  esac
done

if [[ -z "${system}" ]]; then
  system="system"
fi

if [[ -z "${coreId}" ]]; then
  echo "No Solr core id specified!"
  echo ""
  usage
  exit 1
fi

if [[ -z "${remoteCoreName}" ]]; then
  echo "No remote Solr core name specified!"
  echo ""
  usage
  exit 1
fi

currentPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ ! -f "${currentPath}/../env.properties" ]]; then
  echo "No environment specified!"
  exit 1
fi

currentUser="$(whoami)"
currentGroup="$(id -g -n)"

if [[ -z "${dumpFile}" ]] && [[ "${download}" == 1 ]]; then
  if [[ -z "${accessToken}" ]]; then
    "${currentPath}/download-dump.sh" -s "${system}" -n "${remoteCoreName}"
  else
    "${currentPath}/download-dump.sh" -s "${system}" -n "${remoteCoreName}" -a "${accessToken}"
  fi

  date=$(date +%Y-%m-%d)
  dumpFile="${currentPath}/dumps/solr-${remoteCoreName}-${date}.tar.gz"
fi

dumpFileName=$(basename "${dumpFile}")

rm -rf /tmp/solr
mkdir -p /tmp/solr
cp "${dumpFile}" /tmp/solr
cd /tmp/solr
tar -xf "${dumpFileName}" | cat
rm -rf "${dumpFileName}"

solrHost="localhost"
solrUser="solr"
solrGroup="solr"

protocol=$(ini-parse "${currentPath}/../env.properties" "yes" "solr" "protocol")
port=$(ini-parse "${currentPath}/../env.properties" "yes" "solr" "port")
urlPath=$(ini-parse "${currentPath}/../env.properties" "yes" "solr" "urlPath")
user=$(ini-parse "${currentPath}/../env.properties" "no" "solr" "user")
password=$(ini-parse "${currentPath}/../env.properties" "no" "solr" "password")

if [[ -z "${protocol}" ]]; then
  echo "No Solr protocol specified!"
  exit 1
fi

if [[ -z "${port}" ]]; then
  echo "No Solr port specified!"
  exit 1
fi

if [[ -z "${urlPath}" ]]; then
  echo "No Solr url path specified!"
  exit 1
fi

name=$(ini-parse "${currentPath}/../env.properties" "yes" "${coreId}" "name")
instanceDirectory=$(ini-parse "${currentPath}/../env.properties" "yes" "${coreId}" "instanceDirectory")
dataDirectory=$(ini-parse "${currentPath}/../env.properties" "yes" "${coreId}" "dataDirectory")
configFileName=$(ini-parse "${currentPath}/../env.properties" "yes" "${coreId}" "configFileName")

solrDeleteCoreUrl="${protocol}://${solrHost}:${port}/${urlPath}/admin/cores?action=UNLOAD&core=${name}&deleteIndex=true&deleteDataDir=true&deleteInstanceDir=true"

echo "Deleting Solr core with name: ${name}"
if [[ -z "${user}" ]]; then
  curl -s "${solrDeleteCoreUrl}"
else
  curl -s -u "${user}:${password}" "${solrDeleteCoreUrl}"
fi

if [[ "${currentUser}" == "${solrUser}" ]] && [[ "${currentGroup}" == "${solrGroup}" ]]; then
  rm -rf "${instanceDirectory}"

  echo "Creating instance directory at: ${instanceDirectory}"
  mkdir -p "${instanceDirectory}"
  echo "Copying files from: /tmp/solr/instance to: ${instanceDirectory}"
  cp -a /tmp/solr/instance/* "${instanceDirectory}/"
  rm -rf "${instanceDirectory}/core.properties"

  echo "Creating data directory at: ${instanceDirectory}/${dataDirectory}"
  mkdir -p "${instanceDirectory}/${dataDirectory}"
  echo "Copying files from: /tmp/solr/data to: ${instanceDirectory}/${dataDirectory}"
  cp -a /tmp/solr/data/* "${instanceDirectory}/${dataDirectory}/"
else
  sudo rm -rf "${instanceDirectory}"

  echo "Creating instance directory at: ${instanceDirectory}"
  sudo mkdir -p "${instanceDirectory}"
  echo "Copying files from: /tmp/solr/instance to: ${instanceDirectory}"
  sudo cp -a /tmp/solr/instance/* "${instanceDirectory}/"
  sudo rm -rf "${instanceDirectory}/core.properties"
  sudo chown -hR "${solrUser}:${solrGroup}" "${instanceDirectory}"

  echo "Creating data directory at: ${instanceDirectory}/${dataDirectory}"
  sudo mkdir -p "${instanceDirectory}/${dataDirectory}"
  echo "Copying files from: /tmp/solr/data to: ${instanceDirectory}/${dataDirectory}"
  sudo cp -a /tmp/solr/data/* "${instanceDirectory}/${dataDirectory}/"
  sudo chown -hR "${solrUser}:${solrGroup}" "${instanceDirectory}/${dataDirectory}"
fi

cd "${currentPath}"

solrCreateCoreUrl="${protocol}://${solrHost}:${port}/${urlPath}/admin/cores?action=CREATE&name=${name}&instanceDir=${instanceDirectory}&config=${configFileName}&dataDir=${dataDirectory}"

echo "Creating Solr core with name: ${name} in directory: ${instanceDirectory}"
if [[ -z "${user}" ]]; then
  curl -s "${solrCreateCoreUrl}"
else
  curl -s -u "${user}:${password}" "${solrCreateCoreUrl}"
fi

if [[ "${remove}" == 1 ]]; then
  echo "Removing downloaded dump: ${dumpFile}"
  rm -rf "${dumpFile}"
fi
