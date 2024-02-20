#!/usr/bin/env bash

SYSTEM="x86_64-linux"
[ "$(nix eval --impure --raw --expr builtins.currentSystem)" == "$SYSTEM" ] || exit 1

nix build "$PROJECT_URL#typhonProject.actions.$SYSTEM" -o actions

JOBS=$(nix eval --json "$JOBSET_URL#typhonJobs.$SYSTEM" | \
    nix run nixpkgs#jq -- -r 'to_entries | .[] | "[" + (.key | @sh) + "]=" + (.value | @sh)' \
)
declare -A JOBS="($JOBS)"

mk_input() {
    INPUT=$(nix run nixpkgs#jo -- \
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
    nix run nixpkgs#jo -- input=$INPUT secrets=$SECRETS
}

sandbox() {
    nix run nixpkgs#bubblewrap -- \
        --proc /proc \
        --dev /dev \
        --ro-bind /nix/store /nix/store \
        --ro-bind /nix/var/nix /nix/var/nix \
        --ro-bind /etc/reslv.conf /etc/resolv.conf \
        --ro-bind /etc /etc \
        --unshare-pid \
        $1
}

for JOB in ${!JOBS[@]}
do
    DRV=$(nix derivation show "$JOBSET_URL#typhonJobs.$SYSTEM.$JOB" | nix run nixpkgs#jq -- -r 'to_entries | .[] | .key')
    OUT=${JOBS[$JOB]}
    STATUS="pending"

    echo "Job \"$JOB\""

    echo "##[group]Action \"begin\""
    mk_input | actions/begin
    echo "##[endgroup]"

    echo "##[group]Nix build"
    STATUS=$(nix build "$DRV^*" && echo "success" || echo "failure")
    echo "##[endgroup]"

    echo "##[group]Action \"end\""
    mk_input | actions/end
    echo "##[endgroup]"

    echo ""
done
