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
## Outputs

### `file`

Name of the generated release.

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
