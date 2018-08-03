#!/usr/bin/env bash

# Modified version of https://github.com/bellkev/circle-lock-test/blob/4b6ba09dda539f8051f1b6beb72d427f5fa34e19/do-exclusively
# which actually checks the tag sha, rather than expecting it in the commit message
# also adds workflow job option

# sets $branch, $tag, $rest
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--branch) branch="$2" ;;
            -t|--tag) tag="$2" ;;
            -j|--job) job="$2" ;;
            *) break ;;
        esac
        shift 2
    done
    rest=("$@")
}

# reads $branch, $tag, $job
should_skip() {
    if [[ "$branch" && "$CIRCLE_BRANCH" != "$branch" ]]; then
        echo "Not on branch $branch. Skipping..."
        return 0
    fi

    if [[ "$tag" && "$CIRCLE_TAG" != "$tag" ]]; then
        echo "Not on tag $tag. Skipping..."
        return 0
    fi

    if [[ "$job" && "$CIRCLE_JOB" != "$job" ]]; then
        echo "Not running workflow job $job. Skipping..."
        return 0
    fi

    return 1
}

# reads $branch, $tag, $job
# sets $jq_prog
make_jq_prog() {
    local jq_filters=""

    if [[ $branch ]]; then
        jq_filters+=" and .branch == \"$branch\""
    fi

    if [[ $tag ]]; then
        tag_sha=$(git rev-parse --verify $tag)
        jq_filters+=" and .vcs_revision == \"$tag_sha\""
    fi

    if [[ $job ]]; then
        jq_filters+=" and .workflows.job_name == \"$job\""
    fi

    jq_prog=".[] | select(.build_num < $CIRCLE_BUILD_NUM and (.status | test(\"running|pending|queued\")) $jq_filters) | .build_num"
}


if [[ "$0" != *bats* ]]; then
set -e
set -u
set -o pipefail

    branch=""
    tag=""
    rest=()
    api_url="https://circleci.com/api/v1.1/project/github/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME?circle-token=$CIRCLE_TOKEN&limit=100"

    parse_args "$@"
    if should_skip; then exit 0; fi
    make_jq_prog

    echo "Checking for running builds..."

    while true; do
        builds=$(curl -s -H "Accept: application/json" "$api_url" | jq "$jq_prog")
        if [[ $builds ]]; then
            echo "Waiting on builds:"
            echo "$builds"
        else
            break
        fi
        echo "Retrying in 5 seconds..."
        sleep 5
    done

    echo "Acquired lock"

    if [[ "${#rest[@]}" -ne 0 ]]; then
        "${rest[@]}"
    fi
fi
