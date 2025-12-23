#!/bin/bash

set -e

# extract info
if [[ "$GITHUB_REF" == refs/tags/* ]]; then
  echo "tag detected: $GITHUB_REF"
  version=${GITHUB_REF#refs/tags/}
  version=${version#v}
  tagged_version=v${version}
  release=true
elif [[ "$GITHUB_REF" == refs/heads/* ]]; then
  echo "Head ref detected: $GITHUB_REF"
  version=$(echo ${GITHUB_REF#refs/heads/}|tr '/' '_') # Replace / with _ to support PR like renovate/xxxxx
  release=false
elif [[ "$GITHUB_REF" == refs/pull/* ]]; then
  echo "PR detected: $GITHUB_REF"
  pull_number=$(jq --raw-output .pull_request.number "$GITHUB_EVENT_PATH")
  version=pr-${pull_number}
  release=false
fi

echo "*** Inputs ***"
echo "  debug: $INPUT_DEBUG"
echo "  dir: $INPUT_DIR"
echo "  force_version_consistency: $INPUT_FORCE_VERSION_CONSISTENCY"
echo "  override_existing: $INPUT_OVERRIDE_EXISTING"
echo "  repository: $INPUT_REPOSITORY"
echo "  tag_name: $INPUT_TAG_NAME"
echo "  target_branch: $INPUT_TARGET_BRANCH"
echo "  token: **redacted**"

if [[ "$INPUT_DIR" != "." ]];then
  cd "$INPUT_DIR" || exit 1 # We ensure we are in the right directory
  git config --global --add safe.directory "/github/workspace/$INPUT_DIR"
fi
tagged_version=""
if [ -n "$INPUT_TAG_NAME" ];then
  echo "Tag_name detected. Overriding version name and enabling final release. And enforcing 'v' prefix"
  version=$INPUT_TAG_NAME
  version=${version#v}
  tagged_version=v${version}
  release=true
fi

if [ "$INPUT_FORCE_VERSION_CONSISTENCY" == "true" ];then
  echo "Ensure version and tagged_version are identical"
  tagged_version=${version}
fi

if [ "$INPUT_DEBUG" -ne 0 ];then
  echo "Current files before release creation:"
  ls -l
fi

PUSH_TAG_OPTIONS=""
if [ "${INPUT_OVERRIDE_EXISTING}" == "true" ];then
  PUSH_TAG_OPTIONS="--force"
fi

name=$(yq -r .final_name config/final.yml)
if [ "${name}" = "null" ]; then
  name=$(yq -r .name config/final.yml)
fi

remote_repo="https://${GITHUB_ACTOR}:${INPUT_TOKEN}@${GITHUB_SERVER_URL#https://}/${INPUT_REPOSITORY}.git"

# configure git
git config --global user.name "actions/create-bosh-release@v1"
git config --global user.email "<>"
git config --global --add safe.directory /github/workspace
echo "*** Git global config ***"
git --no-pager config --global --list

# remove existing release if any, and prepare a commit that will be amended next
# Having a single amended commit makes it easier to inspect last commit
# See https://superuser.com/a/360986/299481 for details of the bash array syntax
NEXT_GIT_COMMIT_FLAGS=(-m "cutting release ${version}")
FIRST_FINAL_RELEASE="false"
if [ "${release}" == "true" ]; then
  # remove existing release if any
  if [ -f releases/"${name}"/"${name}"-"${version}".yml ]; then
    echo "removing pre-existing version ${version}"
    yq -r "{ \"builds\": (.builds | with_entries(select(.value.version != \"${version}\"))), \"format-version\": .[\"format-version\"]}" < releases/${name}/index.yml > tmp
    mv tmp releases/"${name}"/index.yml
    rm -f releases/"${name}"/"${name}"-"${version}".yml
    git add releases/${name}/${name}-${version}.yml releases/${name}/index.yml
    git commit -a "${NEXT_GIT_COMMIT_FLAGS[@]}"
    NEXT_GIT_COMMIT_FLAGS=(--amend -m "cutting release ${version} overriding existing one")
  else
    FIRST_FINAL_RELEASE="true"
  fi
fi

if [ -n "${AWS_BOSH_ACCES_KEY_ID}" ]; then
  echo "Generating AWS config"
  cat - > config/private.yml <<EOS
---
blobstore:
  options:
    access_key_id: ${AWS_BOSH_ACCES_KEY_ID}
    secret_access_key: ${AWS_BOSH_SECRET_ACCES_KEY}
EOS
elif [ -n "${GCS_JSON_KEY}" ]; then
  echo "Generating GCS config"
  cat - > config/private.yml <<EOS
---
blobstore:
  options:
    credentials_source: static
    json_key: |
      ${GCS_JSON_KEY}
EOS
else
  echo "::warning::AWS_BOSH_ACCES_KEY_ID/AWS_BOSH_SECRET_ACCES_KEY, nor GCS_JSON_KEY set, skipping config/private.yml"
fi

echo "creating bosh release (name: ${name} - version: ${version}): ${name}-${version}.tgz"
if [ "${release}" == "true" ]; then
  bosh create-release --final --version="${version}" --tarball="${name}-${version}".tgz --force # --force is required to ignore dev_releases/ dir, created during final release
else
  bosh create-release --force --timestamp-version --tarball="${name}-${version}".tgz
fi
NEED_GITHUB_RELEASE="false"
if [ "${release}" == "true" ]; then
  echo "adding generated release files to git"
  if [ -d .final_builds ];then
    git add .final_builds
  fi
  git add releases/${name}/index.yml
  RELEASE_FILE_NAME=releases/${name}/${name}-${version}.yml
  git add ${RELEASE_FILE_NAME}
  # Note: if we had removed the previous release, then we amend the commit.
  git commit -a "${NEXT_GIT_COMMIT_FLAGS[@]}"

  echo "Inspecting staged files to skip commit and push if there is no blob changes in the release"
  git show HEAD ${RELEASE_FILE_NAME}
  if [[ $FIRST_FINAL_RELEASE == false ]] && ! git show HEAD ${RELEASE_FILE_NAME} | grep sha1 ; then
    echo "No sha1 found in diff in ${RELEASE_FILE_NAME}. No blob were modified. Skipping the git push"
    ls -al ${RELEASE_FILE_NAME}
    echo " --- Dump ${RELEASE_FILE_NAME} content ---"
    cat ${RELEASE_FILE_NAME}
    echo " --- End dump of ${RELEASE_FILE_NAME} ---"
    NEED_GITHUB_RELEASE="false"
  else
    echo "tagging release ${tagged_version}"
    # Override any existing tag with same version. This may happen if only part of the renovate PRs were merged
    git tag -a -m "cutting release ${tagged_version}" ${tagged_version} $PUSH_TAG_OPTIONS
    echo "Prepare push: rebase changes onto ${INPUT_TARGET_BRANCH}"
    # In case a renovate PR was merged in between, try to rebase prior to pushing
    git pull --rebase "${remote_repo}" "${INPUT_TARGET_BRANCH}"
    if [[ "${INPUT_OVERRIDE_EXISTING}" == "true" ]]; then
      echo "Delete any existing release with same tag. Ignore push failure if no tag exists."
      ! git push --delete "${remote_repo}" ${version}
    fi

    # Try to push up to 3 times if it fails
    max_retries=3
    count=0
    success=false
    while [[ $count -lt $max_retries ]]; do
      echo "pushing changes to git repository on branch ${INPUT_TARGET_BRANCH}"
      if git push ${remote_repo} HEAD:"${INPUT_TARGET_BRANCH}" --follow-tags; then
        success=true
        break
      else
        echo "git push failed. Attempt $((count+1))/$max_retries. Trying to rebase onto ${INPUT_TARGET_BRANCH} and retry..."
        git pull --rebase "${remote_repo}" "${INPUT_TARGET_BRANCH}"
        ((count++))
      fi
    done

    if [[ "$success" == "false" ]]; then
      echo "git push failed after $max_retries attempts."
      exit 1
    fi
    NEED_GITHUB_RELEASE="true"
  fi
fi

if [ "$INPUT_DEBUG" -ne 0 ];then
  echo "Current files after release creation:"
  ls -l
fi


# make asset readable outside docker image
chmod 644 "${name}-${version}.tgz"
# https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#environment-files
echo "file=${name}-${version}.tgz"            >> $GITHUB_OUTPUT
echo "version=${version}"                     >> $GITHUB_OUTPUT
echo "tagged_version=${tagged_version}"       >> $GITHUB_OUTPUT
echo "need_gh_release=${NEED_GITHUB_RELEASE}" >> $GITHUB_OUTPUT

