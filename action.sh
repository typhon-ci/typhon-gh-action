#!/usr/bin/env bash

SYSTEM="x86_64-linux"
[ "$(nix eval --impure --raw --expr builtins.currentSystem)" == "$SYSTEM" ] || exit 1

echo "##[group]Build actions"
ACTIONS=$(nix eval --json "$PROJECT_URL#typhonProject.actions.$SYSTEM" | jq -r)
nix build "$PROJECT_URL#typhonProject.actions.$SYSTEM"
echo "##[endgroup]"

echo "$KEY" > identity.txt
SECRETS=$(cat "$ACTIONS/secrets" | age --decrypt -i identity.txt | jq -c)

JOBS=$(nix eval --json "$JOBSET_URL#typhonJobs.$SYSTEM" | \
    jq -r 'to_entries | .[] | "[" + (.key | @sh) + "]=" + (.value | @sh)' \
)
declare -A JOBS="($JOBS)"

mk_input() {
    INPUT=$(jo \
        drv=$DRV \
        evaluation="00000000-0000-0000-0000-000000000000" \
        flake=true \
        job=$JOB \
        jobset=$JOBSET_NAME \
        out=$OUT \
        project=$PROJECT_NAME \
        status=$STATUS \
        system=$SYSTEM \
        url=$JOBSET_URL \
    )
    jo input=$INPUT secrets=$SECRETS
}

sandbox() {
    bwrap \
        --proc /proc \
        --dev /dev \
        --ro-bind /nix/store /nix/store \
        --ro-bind /nix/var/nix /nix/var/nix \
        --ro-bind /etc/resolv.conf /etc/resolv.conf \
        --clearenv \
        --unshare-pid \
        $1
}

for JOB in ${!JOBS[@]}
do
    DRV=$(nix derivation show "$JOBSET_URL#typhonJobs.$SYSTEM.$JOB" | jq -r 'to_entries | .[] | .key')
    OUT=${JOBS[$JOB]}
    STATUS="pending"

    echo ""
    echo "Job \"$JOB\""

    echo "##[group]Action \"begin\""
    mk_input | sandbox "$ACTIONS/begin"
    echo "##[endgroup]"

    echo "##[group]Nix build"
    STATUS=$(nix build "$DRV^*" && echo "success" || echo "failure")
    echo "##[endgroup]"

    echo "##[group]Action \"end\""
    mk_input | sandbox "$ACTIONS/end"
    echo "##[endgroup]"
done
