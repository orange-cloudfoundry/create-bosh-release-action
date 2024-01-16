#!/bin/bash

set -e

# extract info
if [[ "$GITHUB_REF" == refs/tags/* ]]; then
  version=${GITHUB_REF#refs/tags/}
  version=${version#v}
  release=true
elif [[ "$GITHUB_REF" == refs/heads/* ]]; then
  version=${GITHUB_REF#refs/heads/}
  release=false
elif [[ "$GITHUB_REF" == refs/pull/* ]]; then
  pull_number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
  version=pr-${pull_number}
  release=false
fi

echo "*** Inputs ***"
echo "  dir: $INPUT_DIR"
echo "  repository: $INPUT_REPOSITORY"
echo "  token: **redacted**"
echo "  override_existing: $INPUT_OVERRIDE_EXISTING"
echo "  tag_name: $INPUT_TAG_NAME"
echo "  target_branch: $INPUT_TARGET_BRANCH"
echo "  debug: $INPUT_DEBUG"

if [[ "$INPUT_DIR" != "." ]];then
  cd $INPUT_DIR # We ensure we are in the right directory
  git config --global --add safe.directory /github/workspace/$INPUT_DIR
fi

if [ -n "$INPUT_TAG_NAME" ];then
  echo "Tag_name detected. Overriding version name and enabling final release"
  version=$INPUT_TAG_NAME
  release=true
fi


if [ "$INPUT_DEBUG" -ne 0 ];then
  echo "Current files before release creation:"
  echo "Current files:"
  ls -l
fi

PUSH_OPTIONS=""
if [ "${INPUT_OVERRIDE_EXISTING}" == "true" ];then
  PUSH_OPTIONS="$PUSH_OPTIONS --force"
fi

name=$(yq -r .final_name config/final.yml)
if [ "${name}" = "null" ]; then
  name=$(yq -r .name config/final.yml)
fi

remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@${GITHUB_SERVER_URL#https://}/${GITHUB_REPOSITORY}.git"

# configure git
git config --global user.name "actions/bosh-packager@v2"
git config --global user.email "<>"
git config --global --add safe.directory /github/workspace
echo "*** Git global config ***"
git --no-pager config --global --list

if [ "${release}" == "true" ]; then
  # remove existing release if any
  if [ -f releases/"${name}"/"${name}"-"${version}".yml ]; then
    echo "removing pre-existing version ${version}"
    yq -r "{ \"builds\": (.builds | with_entries(select(.value.version != \"${version}\"))), \"format-version\": .[\"format-version\"]}" < releases/${name}/index.yml > tmp
    mv tmp releases/"${name}"/index.yml
    rm -f releases/"${name}"/"${name}"-"${version}".yml
    git commit -a -m "reset release ${version}"
  fi
fi

if [ -n "${AWS_BOSH_ACCES_KEY_ID}" ]; then
  cat - > config/private.yml <<EOS
---
blobstore:
  options:
    access_key_id: ${AWS_BOSH_ACCES_KEY_ID}
    secret_access_key: ${AWS_BOSH_SECRET_ACCES_KEY}
EOS
else
  echo "::warning::AWS_BOSH_ACCES_KEY_ID not set, skipping config/private.yml"
fi

echo "creating bosh release: ${name}-${version}.tgz"
if [ "${release}" == "true" ]; then
  bosh create-release --force --final --version="${version}" --tarball="${name}-${version}".tgz
else
  bosh create-release --force --timestamp-version --tarball="${name}-${version}".tgz
fi

if [ "${release}" == "true" ]; then
  echo "pushing changes to git repository"
  if [ -d .final_builds ];then
    git add .final_builds
  fi
  git add releases/${name}/index.yml
  git add releases/${name}/${name}-${version}.yml
  git commit -a -m "cutting release ${version}"

  # Override any existing tag with same version. This may happen if only part of the renovate PRs were merged
  git tag -a -m "cutting release ${version}" ${version} $PUSH_OPTIONS

  git pull --rebase ${remote_repo}
  if [ "${INPUT_OVERRIDE_EXISTING}" == "true" ] && git rev-parse "$version" >/dev/null 2>&1; then
    # Delete any existing release with same tag. Ignore push failure if no tag exists.
    git push --delete ${remote_repo} ${version}
  fi

  git push ${remote_repo} HEAD:${INPUT_TARGET_BRANCH} --follow-tags # Push branch and tag
fi

if [ "$INPUT_DEBUG" -ne 0 ];then
  echo "Current files after release creation:"
  ls -l
fi


# make asset readable outside docker image
chmod 644 ${name}-${version}.tgz
# https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#environment-files
echo "file=${name}-${version}.tgz" >> $GITHUB_OUTPUT
echo "version=${version}"          >> $GITHUB_OUTPUT

