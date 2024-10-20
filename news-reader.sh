#!/usr/bin/env bash
set -e

which parallel jq curl xq iconv pandoc jo htmlq > /dev/null
xq -h | grep -q "CSS selector" || { echo "Wrong xq-xml"; exit 4; }

STATEDIR=${STATEDIR:-${XDG_STATE_HOME:-$HOME/.local/state}/news}
CONFIG="$STATEDIR/config.txt"

show-news() {
    jq -r '.pubdate,.title' "$1" | xargs -d'\n' printf "%3d: [%s] %s\n" "$2"
}

parse-news() {
    if [[ "$1" =~ www.cnews.ru ]]; then
        xq -q '.news_container > :not(div, b, nofollow, noindex, aside, section)' -n
    elif [[ "$1" =~ www.opennet.ru ]]; then
        xq -q '.chtext > *' -n | iconv -f koi8-r -t utf-8
    elif [[ "$1" =~ meduza.io ]]; then
        htmlq -r '[data-testid="related-rich-block"]' -r '[data-testid="toolbar"]' \
            -r '[data-testid="material-note"]' '.GeneralMaterial-module-article'
    else
        echo "Unknown portal"
        exit 3
    fi
}

read-news() {
    read -r FILE
    mapfile -t ARGS < <(jq -r '.title,.link,.pubdate' "$FILE")
    mapfile -t < <(curl -s "${ARGS[1]}" \
        | parse-news "${ARGS[1]}" \
        | pandoc -f html -t plain --wrap=none --reference-links)
    printf "Title: %s\nOriginal link: %s\nPublication date: %s\n---\n" "${ARGS[@]}"
    printf "%s\n" "${MAPFILE[@]}"
}

purge-news() {
    while read -r FILE; do # spaces?
        read -r BASEDIR < <(dirname "$FILE" | xargs -I{} dirname "{}")
        read -r DIRNAME < <(dirname "$FILE" | xargs -I{} basename "{}")
        mkdir -p "$BASEDIR/trash"
        mv "$FILE" "$BASEDIR/trash/$DIRNAME-$(basename "$FILE")"
    done
}

update-news() {
    read -r NAME URL
    DIR="$1/$NAME"
    mkdir -p "$DIR"
    mapfile -t CONTENT < <(curl -s "$URL")
    read -r COUNT < <(xq -x "count(//item)" <<< "${CONTENT[@]}")
    for ((i=1; i <= COUNT; ++i)); do
        read -r PUBDATE < <(xq -x "//item[$i]/pubDate" <<< "${CONTENT[@]}" | xargs -I{} date -d "{}" -Is)
        read -r ID < <(date -d "$PUBDATE" +%s)
        read -r LINK < <(xq -x "//item[$i]/link" <<< "${CONTENT[@]}")
        if [[ -e "$DIR/$ID.json" || -e "$1/trash/$NAME-$ID.json" ]]; then
            FILE1="$DIR/$ID.json"
            if [[ ! -e "$FILE1" ]]; then
                FILE1="$1/trash/$NAME-$ID.json"
            fi

            read -r LINK1 < <(jq -r .link "$FILE1")
            if [[ "$LINK1" != "$LINK" ]]; then
                : $((ID++)) # Fix collision
            else
                continue
            fi
        fi

        read -r TITLE < <(xq -x "//item[$i]/title" <<< "${CONTENT[@]}")
        jo link="$LINK" title="$TITLE" pubdate="$PUBDATE" > "$DIR/${ID}.json"
    done

    read -r TITLE < <(xq -x //channel/title <<< "${CONTENT[@]}")
    echo "Processed $COUNT news from $TITLE"
}

export -f show-news read-news purge-news update-news

if [[ "$1" == ls ]]; then
    find "$STATEDIR/$2" -maxdepth 1 -name '*.json' -print | sort -r
elif [[ "$1" == get ]]; then
    $0 ls "$2" | sed -n "$(printf "%sp;" "${@:3}")"
elif [[ "$1" == show ]]; then
    paste <($0 get "${@:2}") <(printf "%s\n" "${@:3}") | parallel -k --colsep '\t' show-news "{1}" "{2}"
elif [[ "$1" == list ]]; then
    $0 ls "$2" | parallel -k show-news "{}" "{#}"
elif [[ "$1" == peek ]]; then
    $0 get "${@:2}" | read-news
elif [[ "$1" == purge ]]; then
    $0 get "${@:2}" | purge-news
elif [[ "$1" == read ]]; then
    $0 peek "${@:2}" && $0 purge "${@:2}"
elif [[ "$1" == next ]]; then
    $0 ls "$2" | wc -l | xargs "$0" read "$2"
elif [[ "$1" == update ]]; then
    awk -vP="$2" '$1 == P {print $0}' "$CONFIG" | update-news "$STATEDIR"
elif [[ "$1" == config ]]; then
    if [[ "$2" == list ]]; then
        awk '{print $1}' "$CONFIG"
    elif [[ "$2" == add ]]; then
        mkdir -p "$STATEDIR" && echo "${@:3}" >> "$CONFIG"
    fi
elif [[ "$1" == help ]]; then
    echo "Usage: $0 ls|get|show|list|peek|read|purge|next|update|config (list|add)|help"
else
    $0 help
    exit 1
fi
