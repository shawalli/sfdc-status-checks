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

PMD_BIN=/opt/pmd/bin/run.sh

# Ensure that we always clean up after ourselves at the first available
# opportunity
function cleanup {
        cd ${ROOTDIR}
        rm -rf results.xml
        rm -rf results.json
}
trap cleanup EXIT

# Parse command line args
SRC_DIR=
HEAD_COMMIT=
TAIL_COMMIT=
PRINT_HELP=

while getopts n:t:s:h option
do
        case "${option}"
        in
                s) SRC_DIR=${OPTARG};;
                n) HEAD_COMMIT=${OPTARG};;
                t) TAIL_COMMIT=${OPTARG};;
                h) PRINT_HELP=1;;
        esac
done

if [[ "x${PRINT_HELP}" != "x" ]]; then
        echo "Usage: lint_check.sh [<options>]"
        echo "Execute lint status check and report results."
        echo
        echo "  -h            print this message and exit"
        echo "  -s=PATH       source directory containing package.xml and metadata"
        echo "  -n=COMMIT     head commit; defaults to HEAD"
        echo "  -t=COMMIT     tail commit; defaults to first parent of head-commit (e.g. if the"
        echo "                head-commit is 'abcdef', the default tail-commit is 'abcdef^')"
        echo

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
echo "* Src Directory:    ${SRC_DIR}"
echo "* Head Commit:      ${HEAD_COMMIT}"
echo "* Tail Commit:      ${TAIL_COMMIT}"

echo "====Apex Class Changes===="
CHANGED_CLASSES=(`git diff-tree --no-commit-id --name-only --diff-filter=ACMTUXB -r ${TAIL_COMMIT} ${HEAD_COMMIT} -- ${SRC_DIR}/classes ${SRC_DIR}/triggers`)
echo "================================"

if [[ ${#CHANGED_CLASSES[@]} -gt 0 ]]; then
        CHANGED_CLASSES_FLAT=`printf "%s," "${CHANGED_CLASSES[@]}"`
        CHANGED_CLASSES_FLAT=${CHANGED_CLASSES_FLAT::-1}

        invoke "
        ${PMD_BIN} pmd \
        -format xml \
        -rulesets ./assets/base_linting_ruleset.xml \
        -reportfile ./results.xml \
        -language apex \
        -shortnames	\
        -dir \"${CHANGED_CLASSES_FLAT}\""

        EXIT_CODE=`echo $?`

        python -c "import json
import xmltodict
with open('results.xml') as fh:
    xml = fh.read()
print(json.dumps(xmltodict.parse(xml)))" > results.json

        sed -i 's/\@//g' results.json
        sed -i 's/#text/message/g' results.json

        CHANGED_CLASSES_FLAT=`printf "\'%s\'," "${CHANGED_CLASSES[@]}"`
        CHANGED_CLASSES_FLAT=${CHANGED_CLASSES_FLAT::-1}
        CHANGED_CLASSES_FLAT="[${CHANGED_CLASSES_FLAT}]"
else
        echo "{}" > results.json

        EXIT_CODE=0

        CHANGED_CLASSES_FLAT="[]"
fi

#### Report results back to GitHub as commit comment or Pull Request comment ####

if [[ "${EXIT_CODE}" != "0" ]]; then
        echo "Detected syntax validation failure"
        exit 1
else
        echo "Syntax validation succeeded"
fi

exit 0