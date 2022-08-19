#!/usr/bin/env bash

get_layers() {
    local repo=$1
    local digest=$2

    # If the repo is GHCR
    if [[ $repo == ghcr.io/* ]]; then
        local clean_repo=${repo#"ghcr.io/"}
        local manifestURL="https://ghcr.io/v2/${clean_repo}/manifests/${digest}"
    else
        local manifestURL="https://index.docker.io/v2/${repo}/manifests/${digest}"
    fi

    # get initial manifest
    digestOutput=$(curl -s \
        -H "Authorization: Bearer $(get_token $repo)" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        $manifestURL
        2>/dev/null \
    )

    # if this tag has multiple archs, handle properly
    if [[ $(echo $digestOutput | jq -r '.manifests != null') == "true" ]]; then

        # extract the digest for amd64
        local sha=$(cat text | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')
        local manifestURL=${manifestURL/'manifests/'$digest/'manifests/'$sha}

        # get new information
        digestOutput=$(curl -s \
            -H "Authorization: Bearer $(get_token $repo)" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            $manifestURL
            2>/dev/null \
        )
    fi

    # get layers from digest
    jq -r '[.layers[].digest]' <<<"$digestOutput"

}

get_token() {
    local repo=$1

    # If the repo is GHCR
    if [[ $repo == ghcr.io/* ]]; then

        # Make sure PAT is set
        if [[ ${ghcr_user:-none} == "none" || ${ghcr_token:-none} == "none" ]]; then
            >&2 echo "ERROR: GHCR User or Token Unset!"
            exit -1
        fi

        # Get temp token with read access to repo
        echo $(curl -s \
            -u $ghcr_user:$ghcr_token \
            'https://ghcr.io/token?scope="repository:'${repo}':pull"' \
            2>/dev/null | jq -r '.token' \
        )

    # Else, assume Docker
    else
        echo $(curl -s \
            'https://auth.docker.io/token?service=registry.docker.io&scope=repository:'${repo}':pull' \
            2>/dev/null | jq -r '.token' \
        )
    fi
}

IFS=: read base base_tag <<<$base
IFS=: read image image_tag <<<$image

layers_base=$(get_layers $base ${base_tag:-latest})
layers_image=$(get_layers $image ${image_tag:-latest})

jq '.base-.image | .!=[]' <<<"{\"base\": $layers_base, \"image\": $layers_image }"