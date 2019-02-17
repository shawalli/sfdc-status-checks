#/usr/bin/env bash

# Convenience method
invoke() {
        echo "CMD: $1"
        eval $1
}

# Make sure we are in the root directory
ROOTDIR=${0}
ROOTDIR=`realpath ${ROOTDIR}`
ROOTDIR=${ROOTDIR%%\/status_checks/*}
if [[ "${ROOTDIR}" != "$(pwd)" ]]; then
        cd ${ROOTDIR} && echo "Changing to root directory at: ${ROOTDIR}"
fi

# Ensure that we always clean up after ourselves at the first available
# opportunity
function cleanup {
        cd ${ROOTDIR}
        rm -rf results.json
        rm -rf build
}
trap cleanup EXIT

# Parse command line args
TARGET_ORG_ALIAS=
SRC_DIR=
HEAD_COMMIT=
TAIL_COMMIT=
PRINT_HELP=

while getopts a:n:t:s:h option
do
        case "${option}"
        in
                a) TARGET_ORG_ALIAS=${OPTARG};;
                s) SRC_DIR=${OPTARG};;
                n) HEAD_COMMIT=${OPTARG};;
                t) TAIL_COMMIT=${OPTARG};;
                h) PRINT_HELP=1;;
        esac
done

if [[ "x${PRINT_HELP}" != "x" ]]; then
        echo "Usage: changeset_check.sh [<options>]"
        echo "Execute change set status check and report results."
        echo
        echo "  -h            print this message and exit"
        echo "  -a=ALIAS      target org alias"
        echo "  -s=PATH       source directory containing package.xml and metadata"
        echo "  -n=COMMIT     head commit; defaults to HEAD"
        echo "  -t=COMMIT     tail commit; defaults to first parent of head-commit (e.g. if the"
        echo "                head-commit is 'abcdef', the default tail-commit is 'abcdef^'"
        echo

        exit 1
fi

if [[ "x${TARGET_ORG_ALIAS}" == "x" ]]; then
        echo "Missing required flag '-t ALIAS'"
        exit 1
fi

if [[ "x${SRC_DIR}" == "x" ]]; then
        SRC_DIR=src
fi

if [[ "x${HEAD_COMMIT}" == "x" ]]; then
        HEAD_COMMIT=HEAD
fi

if [[ "x${TAIL_COMMIT}" == "x" ]]; then
        TAIL_COMMIT="${HEAD_COMMIT}^"
fi

echo "====Settings===="
echo "* Target Org Alias: ${TARGET_ORG_ALIAS}"
echo "* Src Directory:    ${SRC_DIR}"
echo "* Head Commit:      ${HEAD_COMMIT}"
echo "* Tail Commit:      ${TAIL_COMMIT}"

invoke "./utils/git_diff_packager.sh -t ${TAIL_COMMIT} -n ${HEAD_COMMIT} -s ${SRC_DIR}"

if [[ $? != 0 ]]; then
        echo "Packaging failed"
        exit 1
fi

invoke "sfdx force:mdapi:deploy --targetusername ${TARGET_ORG_ALIAS} --checkonly --wait -1 --zipfile build/deploy/unpackaged.zip --json > results.json"

PKG_RESULT=`jq -r '.result.status' results.json`
echo "Package validation result: \"${PKG_RESULT}\""

#### Report results back to GitHub as commit comment or Pull Request comment ####

PKG_STATUS_CODE=`jq -r '.status' results.json`
if [[ "${PKG_STATUS_CODE}" != "0" ]]; then
        echo "Detected package validation failure"

        exit 1
else
        echo "Package validation succeeded"
fi

exit 0