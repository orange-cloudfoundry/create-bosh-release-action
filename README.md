#  Bosh release action

Github action to generate a new version of bosh final release

## Inputs

### `target_branch`

The name of the branch where generated release files should be pushed. Default `"master"`.

### `tag_name`
Tag name used to create the bosh release. Leave it empty to autodetect

required: `false`

### `override_existing`
override existing tag or release

required: `false`
default: `false`

### `dir`
Release directory path if not current working directory

required: `false`
default: `.`

### `debug`
Set to 1 to enable debug mode

default: 0

### `force_version_consistency`
Ensure output tagged_version and version are always identical, using version as source. Otherwise, 'tagged_version' starts with 'v' prefix.Default: false.

required: `false`
default: `false`

## Outputs

### `file`

Name of the generated release.

### `version`

version of the generated bosh release

### `need_gh_release`

Do we need to create a GitHub release associated to this bosh release

### `tagged_version`

Only set when a final release is created, otherwise it is empty. It matches 'version', but always starts with 'v'.
## Example usage

```
uses: orange-cloudfoundry/bosh-release-action@v2
with:
  target_branch: master
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  AWS_BOSH_ACCES_KEY_ID: ${{ secrets.AWS_BOSH_ACCES_KEY_ID }}
  AWS_BOSH_SECRET_ACCES_KEY: ${{ secrets.AWS_BOSH_SECRET_ACCES_KEY }}
```

See [GitHub action for extra samples](./.github/workflows/on-commit.yml)
