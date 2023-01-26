#!/bin/bash
USAGE="$(basename "$0") [ -h ] [ -v version]
-- Build and publish image to docker registry
-- Flags:
      -h  shows help
      -v  version [ i.e. 1.0, 2.2,... ]"

VERSION=0

# Get configuration
while getopts 'hd:v:l' OPTION; do
case "$OPTION" in
    h)
    echo "$USAGE"
    exit 0
    ;;
    v)
    VERSION="$OPTARG"
    ;;
    l)
    LATEST="1";
    ;;
esac
done

# Update to VERSION if any
if [ ${VERSION} == 0 ]
then
   echo "No version specified, closing.."
   say "Please specify a version"
   exit 1
fi
# Udpate version file
echo ${VERSION} > VERSION
git add VERSION
git commit -m "Updated version to ${VERSION}"

# Create tag
git tag -a ${VERSION}
git push github --tags
say 'Done!'

