#/usr/bin/env bash
#
# This script creates a Salesforce change set zip based on two Git commits.
# It was originally inspired by the following article, though is has been
# significantly modified since then.
# https://apexandbeyond.wordpress.com/2017/03/15/dynamic-package-xml-generation

# Make sure we are in the root directory
ROOTDIR=${0}
ROOTDIR=`realpath ${ROOTDIR}`
ROOTDIR=${ROOTDIR%%\/utils/*}
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

# Parse command line args
BUILD_DIR=
SRC_DIR=
HEAD_COMMIT=
TAIL_COMMIT=
PRINT_HELP=

while getopts b:n:t:s:h option
do
        case "${option}"
        in
                b) BUILD_DIR=${OPTARG};;
                s) SRC_DIR=${OPTARG};;
                n) HEAD_COMMIT=${OPTARG};;
                t) TAIL_COMMIT=${OPTARG};;
                h) PRINT_HELP=1;;
        esac
done

if [[ "x${PRINT_HELP}" != "x" ]]; then
        echo "Usage: git_diff_packager.sh [<options>]"
        echo "Create a change-set zip based on the changes between Git commits."
        echo
        echo "  -h            print this message and exit"
        echo "  -b=PATH       directory that should be used for the package build"
        echo "  -s=PATH       source directory containing package.xml and metadata"
        echo "  -n=COMMIT     head commit; defaults to HEAD"
        echo "  -t=COMMIT     tail commit; defaults to first parent of head-commit (e.g. if the"
        echo "                head-commit is 'abcdef', the default tail-commit is 'abcdef^'"
        echo

        exit 1
fi

if [[ "x${BUILD_DIR}" == "x" ]]; then
        BUILD_DIR=build/deploy
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

PACKAGE_XML=${SRC_DIR}/package.xml
PACKAGE_XML_TEMPLATE=assets/${PACKAGE_XML}.template


# Ensure that we always clean up after ourselves at the first available
# opportunity
function cleanup {
        echo ====Cleaning up project====
        cd ${ROOTDIR}
        if [[ -f ./package.xml.bak ]]; then
                mv package.xml.bak ${PACKAGE_XML} && echo "Restoring package.xml"
        fi
}
trap cleanup EXIT

echo "====Settings===="
echo "* Deploy Directory: ${BUILD_DIR}"
echo "* Src Directory:    ${SRC_DIR}"
echo "* Head Commit:      ${HEAD_COMMIT}"
echo "* Tail Commit:      ${TAIL_COMMIT}"
echo "* Package XML:      ${PACKAGE_XML}"

echo "====Set-up===="
if [ -d "${BUILD_DIR}" ]; then
    echo "* Removing deploy directory"
    rm -rf "${BUILD_DIR}"
fi
mkdir -p ${BUILD_DIR} && echo "* Creating deploy dir at: ${BUILD_DIR}"
cp ${PACKAGE_XML} package.xml.bak && echo "* Backing up ${PACKAGE_XML} to: package.xml.bak"

cat ${PACKAGE_XML_TEMPLATE} > ${PACKAGE_XML}
echo "====Delta Changes===="
git diff-tree --no-commit-id --name-only --diff-filter=ACMTUXB -r ${TAIL_COMMIT} ${HEAD_COMMIT} -- ${SRC_DIR}

echo "====Generating deploy package===="
while read -r CFILE; do
        if [[ ${CFILE} == *"${SRC_DIR}/"*"."* ]]; then
                tar cf - "${CFILE}"* | (cd ${BUILD_DIR}; tar xf -)
        fi
        if [[ ${CFILE} == *"-meta.xml" ]]; then
                ADDFILE=${CFILE}
                ADDFILE="${ADDFILE%-meta.xml*}"
                tar cf - ${ADDFILE} | (cd ${BUILD_DIR}; tar xf -)
        fi
        if [[ ${CFILE} == *"/aura/"*"."* ]]; then
                DIR=$(dirname "${CFILE}")
                tar cf - ${DIR} | (cd ${BUILD_DIR}; tar xf -)
        fi

        case "${CFILE}"
        in
                */applications/*.app*) TYPENAME="CustomApplication";;
                *.approvalProcess*) TYPENAME="ApprovalProcess";;
                *.assignmentRules*) TYPENAME="AssignmentRules";;
                */aura/*) TYPENAME="AuraDefinitionBundle";;
                *.autoResponseRules*) TYPENAME="AutoResponseRules";;
                */cachePartition/*.cachePartition*) TYPENAME="PlatformCachePartition";;
                */classes/*.cls*) TYPENAME="ApexClass";;
                */communities/*.community*) TYPENAME="Community";;
                *.component*) TYPENAME="ApexComponent";;
                *.customApplicationComponent*) TYPENAME="CustomApplicationComponent";;
                */customMetadata/*.md*) TYPENAME="CustomMetadata";;
                *.customPermission*) TYPENAME="CustomPermission";;
                */documents/*.*) TYPENAME="Document";;
                */email/*.email*) TYPENAME="EmailTemplate";;
                */email/*-meta.xml) TYPENAME="EmailTemplate";;
                *.escalationRules*) TYPENAME="EscalationRules";;
                */globalValueSets/*.globalValueSet*) TYPENAME="GlobalValueSet";;
                *.globalValueSetTranslation*) TYPENAME="GlobalValueSetTranslation";;
                */groups/*.group*) TYPENAME="Group";;
                */homePageComponent/*.homePageComponent*) TYPENAME="HomePageComponent";;
                */homePageLayout/*.homePageLayout*) TYPENAME="HomePageLayout";;
                */labels/*.labels*) TYPENAME="CustomLabels";;
                */layouts/*.layout*) TYPENAME="Layout";;
                *.letter*) TYPENAME="Letterhead";;
                */objects/*.object*) TYPENAME="CustomObject";;
                */objects/*__*__c.object*) TYPENAME="UNKNOWN TYPE";; # We don't want objects from managed packages to be deployed;;
                */objectTranslation/*.objectTranslation*) TYPENAME="CustomObjectTranslation";;
                *OrgPreference.settings*) TYPENAME="UNKNOWN TYPE";;
                */pages/*.page*) TYPENAME="ApexPage";;
                */permissionsets/*.permissionset*) TYPENAME="PermissionSet";;
                */profiles/*.profile*) TYPENAME="Profile";;
                */reportTypes/*.reportType*) TYPENAME="ReportType";;
                */roles/*.role*) TYPENAME="Role";;
                */settings/*.settings*) TYPENAME="Settings";;
                *.snapshot*) TYPENAME="AnalyticSnapshot";;
                */standardValueSets*.standardValueSet*) TYPENAME="StandardValueSet";;
                *.standardValueSetTranslation*) TYPENAME="StandardValueSetTranslation";;
                */staticresources/*.resource*) TYPENAME="StaticResource";;
                */tabs/*.tab*) TYPENAME="CustomTab";;
                *.translation*) TYPENAME="Translations";;
                */triggers/*.trigger*) TYPENAME="ApexTrigger";;
                *.weblink*) TYPENAME="CustomPageWebLink";;
                */workflows/*.workflow*) TYPENAME="Workflow";;
                *) TYPENAME="UNKNOWN TYPE";;
        esac

        if [[ "${TYPENAME}" != "UNKNOWN TYPE" ]]; then
                case "${CFILE}"
                in
                        */email/*) ENTITY="${CFILE#*/email/}";;
                        */documents/*) ENTITY="${CFILE#*/documents/}";;
                        */aura/*) ENTITY="${CFILE#*/aura/}" ENTITY="${ENTITY%/*}";;
                        *) ENTITY=$(basename "${CFILE}");;
                esac

                if [[ ${ENTITY} == *"-meta.xml" ]]; then
                        ENTITY="${ENTITY%%.*}"
                        ENTITY="${ENTITY%-meta*}"
                else
                        ENTITY="${ENTITY%.*}"
                fi

                # Matches if entity already exists for same metadata type with this name
                # Protects against duplicates WRT meta files
                EXISTING_METADATA=$(${XMLSTARLET_BIN} sel -t -c "//Package/types[name='${TYPENAME}' and members='${ENTITY}']" ${PACKAGE_XML})
                if [[ "x${EXISTING_METADATA}" != "x" ]]; then
                        continue
                fi

                echo "* Adding ${TYPENAME}: ${ENTITY}"

                if grep -Fq "<name>${TYPENAME}</name>" ${PACKAGE_XML}; then
                        ${XMLSTARLET_BIN} ed -L -s "//Package/types[name='${TYPENAME}']" -t elem -n members -v "${ENTITY}" ${PACKAGE_XML}
                else
                        ${XMLSTARLET_BIN} ed -L -s "//Package" -t elem -n types -v "" ${PACKAGE_XML}
                        ${XMLSTARLET_BIN} ed -L -s "//Package/types[not(*)]" -t elem -n name -v "${TYPENAME}" ${PACKAGE_XML}
                        ${XMLSTARLET_BIN} ed -L -s "//Package/types[name='${TYPENAME}']" -t elem -n members -v "${ENTITY}" ${PACKAGE_XML}
                fi
        fi
done <<< "$(git diff-tree --no-commit-id --name-only --diff-filter=ACMTUXB -r ${TAIL_COMMIT} ${HEAD_COMMIT} -- ${SRC_DIR})"

echo ====Bundling final package=====
${XMLSTARLET_BIN} ed -L -i "//Package" -t attr -n xmlns -v "http://soap.sforce.com/2006/04/metadata" ${PACKAGE_XML}

echo "Moving package.xml to deploy dir"
tar cf - ${PACKAGE_XML} | (cd ${BUILD_DIR}; tar xf -)
cd ${BUILD_DIR} && echo "Changing directory into deploy directory: ${BUILD_DIR}"
python -mzipfile -c unpackaged.zip src && echo "Zipping project at: ${BUILD_DIR}/unpackaged.zip"
