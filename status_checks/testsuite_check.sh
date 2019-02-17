#/usr/bin/env bash

# Make sure we are in the root directory
ROOTDIR=${0}
ROOTDIR=`realpath ${ROOTDIR}`
ROOTDIR=${ROOTDIR%%\/status_checks/*}
if [[ "${ROOTDIR}" != "$(pwd)" ]]; then
        cd ${ROOTDIR} && echo "Changing to root directory at: ${ROOTDIR}"
fi

# Find XMLStarlet
XMLSTARLET_BIN=
which xmlstarlet 1>/dev/null 2>&1 && XMLSTARLET_BIN=xmlstarlet
which xml 1>/dev/null 2>&1 && XMLSTARLET_BIN=xml

if [[ "x${XMLSTARLET_BIN}" == "x" ]]; then
        echo "No xmlstarlet found; exiting"
        exit 1
fi

# Ensure that we always clean up after ourselves at the first available
# opportunity
function cleanup {
        cd ${ROOTDIR}
        rm -rf testsuite_comment.md
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
        echo "Usage: testsuite_check.sh [<options>]"
        echo "Execute test-suite status check and report results."
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

echo "====Delta Changes===="
git diff-tree --no-commit-id --name-only --diff-filter=ACMTUXB -r ${TAIL_COMMIT} ${HEAD_COMMIT} -- ${SRC_DIR}/classes

echo "==== Test Class Analysis ===="
echo "Finding orphan test classes..."
ORPHAN_TEST_CLASSES=()
while read -r MATCH; do
        if [[ "x${MATCH}" == "x" ]]; then
                continue
        fi
        TEST_CLASS=`echo ${MATCH} | sed 's/\([^:]*\):.*/\1/g'`
        echo "* Analyzing: ${TEST_CLASS}..."

        CLASS_NAME=${TEST_CLASS##*/}
        CLASS_NAME=${CLASS_NAME%%.cls}

        FOUND=
        while read -r TEST_SUITE; do
                RESULT=`${XMLSTARLET_BIN} sel -N x="http://soap.sforce.com/2006/04/metadata" -t -c "//x:ApexTestSuite/x:testClassName[text()=\"${CLASS_NAME}\"]" ${TEST_SUITE}`
                if [[ "x${RESULT}" != "x" ]]; then
                        FOUND=1
                        break
                fi
        done <<< "$(find src/testSuites/ -type f -print)"

        if [[ "x${FOUND}" == "x" ]]; then
                ORPHAN_TEST_CLASSES+=("${TEST_CLASS}")
        fi
done <<< "$(git diff-tree --no-commit-id --name-only --diff-filter=ACMTUXB -r ${TAIL_COMMIT} ${HEAD_COMMIT} -- ${SRC_DIR}/classes | xargs grep -m1 -i '@istest')"

#### Report results back to GitHub as commit comment or Pull Request comment ####

echo "====Results===="
if [[ ${#ORPHAN_TEST_CLASSES[@]} -gt 0 ]]; then
        echo "Found ${#ORPHAN_TEST_CLASSES[@]} unit tests that are not registered in any test suite"
        printf '* %s\n' "${ORPHAN_TEST_CLASSES[@]}"
        exit 1
else
        echo "No orphaned unit tests found"
        exit 0
fi