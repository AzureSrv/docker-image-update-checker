# Docker Image Update Checker Action

[![Test](https://github.com/lucacome/docker-image-update-checker/actions/workflows/test.yml/badge.svg)](https://github.com/azuresrv/docker-image-update-checker/actions/workflows/test.yml)
[![GitHub license badge](https://badgen.net/github/license/lucacome/docker-image-update-checker)](https://github.com/azuresrv/docker-image-update-checker/blob/main/LICENSE)

Action to check if an image's base layers differ from its upstream's. (i.e. Detects an update to the upstream.) This action will use GHCR/Docker's API to compare the base layers of your image with the `upstream`, without the need to pull the images.


## Inputs

| Name                | Type     | Description                                   |
|---------------------|----------|-----------------------------------------------|
| `upstream`          | String   | Base Docker Image                             |
| `target`            | String   | Your image based on `upstream`                |
| `ghcr_user`         | String   | Your GitHub Username                          |
| `ghcr_token`        | String   | A GitHub PAT with the `read:packages` scope   |

## Output

| Name             | Type    | Description                                                |
|------------------|---------|------------------------------------------------------------|
| `needs-updating` | String  | 'true' or 'false', if the image needs to be updated or not |


## Example

```yaml
name: check docker images

on:
  schedule:
    - cron:  '0 4 * * *'

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      -
        name: Checkout
        uses: actions/checkout@v2
      -
        name: Check if update available
        id: check
        uses: azuresrv/docker-image-update-checker@v2
        with:
          upstream: library/nginx:1.21.0
          target: user/app:latest
      -
        name: Build and push
        uses: docker/build-push-action@v2
        with:
          context: .
          push: true
          tags: user/app:latest
        if: steps.check.outputs.needs-updating == 'true'
```
