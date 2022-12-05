#!/usr/bin/env bash

get_dockerio_token() {
    local name=$1
    local user=$2

    # send request
    res=$(curl -s \
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:'$user/$name':pull' \
        2>/dev/null \
    )

    # print out token (or null if bad)
    token=$(jq -r '.token' <<< $res)
    if [[ ${token:-none} == "none" ]]; then
        >&2 echo "::error Failed to get token for docker.io!"
        exit 1
    fi
    echo $token
}

get_ghcrio_token() {
    local name=$1
    local user=$2

    # send request
    res=$(curl -s \
        -u $ghcr_user:$ghcr_token \
        'https://ghcr.io/token?scope="repository:'$user/$name':pull"' \
        2>/dev/null \
    )

    # print out token (or null if bad)
    token=$(jq -r '.token' <<< $res)
    if [[ ${token:-none} == "none" ]]; then
        >&2 echo "::error Failed to get token for ghcr.io!"
        exit 1
    fi
    echo $token
}

get_layers() {
    local host=$1
    local user=$2
    local name=$3
    local digest=$4

    # format data for request
    if [[ $host == "docker.io" ]]; then
        local manifestURL="https://index.docker.io/v2/$user/$name/manifests/$digest"
        local token=$(get_dockerio_token $name $user)
    elif [[ $host == "ghcr.io" ]]; then
        local manifestURL="https://ghcr.io/v2/$user/$name/manifests/$digest"
        local token=$(get_ghcrio_token $name $user)
    else
        >&2 echo "::error Bad/Unsupported Host passed to get_layers!"
        exit 1 # 1 - Bad/Unsupported host
    fi

    # make sure tokens didnt return an error
    if [[ $? -ne 0 ]]; then
        exit 2 # 2 - bad token
    fi

    # get initial manifest
    digestOutput=$(curl -s \
        -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        $manifestURL
        2>/dev/null \
    )

    # if this tag has multiple archs, handle properly
    if [[ $(echo $digestOutput | jq -r '.manifests != null') == "true" ]]; then

        # extract the digest for amd64
        local sha=$(echo $digestOutput | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')
        local manifestURL=${manifestURL/'manifests/'$digest/'manifests/'$sha}

        # get new arch-specific manitest
        digestOutput=$(curl -s \
            -H "Authorization: Bearer $token" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            $manifestURL
            2>/dev/null \
        )
    fi

    # get layers from digest
    jq -r '[.layers[].digest]' <<< $digestOutput

}

# nice starting echo
echo "-- Docker Image Update Checker --"
echo "\"This action's name should really be shorter!\""
echo ""

# make sure targets are defined
if [[ ${upstream:-none} == "none" || ${target:-none} == "none" ]]; then
    echo "::error Upstream or Target not defined! Exiting..."
    exit -1
fi

# split input into image and tag
echo "Parsing tags..."
IFS=: read upstream up_tag <<<$upstream
IFS=: read target tg_tag <<<$target

# reverse image strings
upstream=$(tr '/' $'\n' <<< $upstream | tac | paste -s -d '/')
target=$(tr '/' $'\n' <<< $target | tac | paste -s -d '/')

# split these up too
IFS=/ read up_name up_user up_host <<< $upstream
IFS=/ read tg_name tg_user tg_host <<< $target

# set defaults in case of blanks
up_host=${up_host:-docker.io}; up_user=${up_user:-library}; up_tag=${up_tag:-latest}
tg_host=${tg_host:-docker.io}; tg_user=${tg_user:-library}; tg_tag=${tg_tag:-latest}

# echo for debugging later :)
echo " - Upstream: $up_host $up_user $up_name $up_tag"
echo " - Target: $tg_host $tg_user $tg_name $tg_tag"

# if GHCR, make sure proper auth vars are set
if [[ $up_host == "ghcr.io" || $tg_host == "ghcr.io" ]]; then
    if [[ ${ghcr_user:-none} == "none" || ${ghcr_token:-none} == "none" ]]; then
        echo "::error ERROR: GHCR User or Token Unset!"
        exit -1
    fi
fi

# get layers for both images
echo "Downloading manifests..."
layers_upstream=$(get_layers $up_host $up_user $up_name $up_tag)
layers_target=$(get_layers $tg_host $tg_user $tg_name $tg_tag)

# compare two images
echo "Comparing manifests..."
json="{\"upstream\": $layers_upstream, \"target\": $layers_target }"
update_needed=$(jq '.upstream-.target | .!=[]' <<<$json)

# write output
echo "needs-updating=${update_needed}" >> $GITHUB_OUTPUT

# finish up
echo "Done! Update needed: ${update_needed}"
