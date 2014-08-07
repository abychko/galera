#!/bin/bash
# Usage: build-dpkg-for-archive.sh [options] [source-dir] [working-dir]
#
# The program will setup the dpkg building environment and ultimately call
# dpkg-buildpackage with the appropiate parameters.
#

# Bail out on errors, be strict
set -ue

# The location of the source tree to build
SOURCE_DIR=''

# The working directory and location of resulting files
WORKING_DIR=''

# Build binary packages after source packages
BUILD_BINARY=''

# Read from the VERSION file
GALERA_VERSION=''

# git revno
GALERA_REVISION=''

# The .orig tar file name
ORIG_TAR=''

# The directory that the .orig tar is expanded to
ORIG_TAR_DIR=''

# The resulting .dsc file from the debian build
DSC_FILE=''

# Display usage
function show_usage()
{
	if [ $# -gt 1 ]; then
		echo "ERROR : ${2}"
	fi

	echo \
"Usage:
	$(basename $0) [options] [source-dir] [working-dir]
Options:
	-b | --binary	Build binary packages after source packages have been built.
	-h | --help	Display this help message."
	exit $1
}

# Examine parameters
go_out="$(getopt --options="bhs" --longoptions="binary,help,skip-mtr" \
	--name="$(basename "$0")" -- "$@")"
eval set -- "$go_out"

for arg
do
	case "$arg" in
	-- ) shift; break;;
	-b | --binary ) shift; BUILD_BINARY='true';;
	-h | --help ) shift; show_usage 0;;
	esac
done

if [ $# -eq 0 ]; then
	show_usage 1 "No source-dir specified"
fi
SOURCE_DIR=$1; shift;
if [ ! -d "${SOURCE_DIR}" ]; then
	show_usage 1 "Invalid source-dir specified \"${SOURCE_DIR}\""
fi

if [ $# -eq 0 ]; then
	show_usage 1 "No working-dir specified"
fi
WORKING_DIR=$1; shift;
if [ ! -d "${SOURCE_DIR}" ]; then
	show_usage 1 "Invalid working-dir specified \"${WORKING_DIR}\""
fi


echo "BUILD_BINARY=${BUILD_BINARY}"
echo "SOURCE_DIR=${SOURCE_DIR}"
echo "WORKING_DIR=${WORKING_DIR}"

# And away we go...
echo "Building orig tarball..."
cd ${SOURCE_DIR}

# Collect versions stuffs
GALERA_VERSION=$(grep '^GALERA_VER' SConstruct  | grep -oE "'[0-9.]+'" | tr -d "'")
GALERA_REVISION="$(git rev-list --count HEAD)"

# Build out various file and directory names
ORIG_TAR=percona-xtradb-cluster-galera-3.x_${GALERA_VERSION}.orig.tar.gz
ORIG_TAR_DIR=percona-xtradb-cluster-galera-3.x_${GALERA_VERSION}

# Remove anything not needed for debian build.
#
# Move the debian directory out of the way and save it for later
mv -v debian ${WORKING_DIR}

# Relocate to the working dir
cd ${WORKING_DIR}

# Rename the tree
mv ${SOURCE_DIR} ${ORIG_TAR_DIR}

# Build the orig tarfile
tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${ORIG_TAR} ${ORIG_TAR_DIR}
echo "Orig tarball built"
echo "Building debian source package..."

# Move the previously saved debian directory into the root of the orig source tree
mv -v debian ${ORIG_TAR_DIR}

# Change into the orig source tree
cd ${ORIG_TAR_DIR}

# Call the debian build system to build the source package
dpkg-buildpackage -S

# Change back to the working dir
cd ${WORKING_DIR}
echo "Debian source package built"
echo "Testing source package..."

# Find the .dsc file that should have been created by the debian package build
DSC_FILE=$(basename $(find . -type f -name '*.dsc' | sort | tail -n1))
if [ -z "${DSC_FILE}" ]; then
	echo "ERROR : Could not find resulting debian dsc file"
fi

# Let's test it
lintian --verbose --info --pedantic ${DSC_FILE} | tee ${WORKING_DIR}/lintian.log
echo "Source package tested"

# Are we done?
if [ "${BUILD_BINARY}" != "true" ]; then
	exit 0
fi


# Now, lets build the binary package
echo "Building binary packages..."
cd ${ORIG_TAR_DIR}
dpkg-buildpackage -rfakeroot -uc -us -b

# Change back to the working dir
cd ${WORKING_DIR}
echo "Debian binary packages built"
echo "Testing binary packages..."

# Find the .deb files that should have been created by the debian package build
for DEB_FILE in $(find . -type f -name '*.deb' | sort); do
	echo "Testing ${DEB_FILE}..."
	lintian --verbose --info --pedantic ${DEB_FILE} | tee -a ${WORKING_DIR}/lintian.log
	echo "${DEB_FILE} tested"
done
echo "Binary packages tested"

exit 0
