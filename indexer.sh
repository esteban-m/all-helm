#!/bin/bash

INPUT_FILE="urls.txt"
MEGA_INDEX="index.yaml"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

NUM_JOBS=5        # Parallélisme max
PER_REQ_TIMEOUT=8 # Timeout par URL en secondes

pids=()
files=()

process_url_bg() {
  local url="$1"
  local outfile="$2"

  echo "→ [$url] => Téléchargement..."

  if content=$(curl --max-time "$PER_REQ_TIMEOUT" -sfL "$url"); then
    if echo "$content" | yq e '.' - >/dev/null 2>&1; then
      entries=$(echo "$content" | yq e '.entries // {}' -)
      if [[ $(echo "$entries" | yq e 'length' -) -ne 0 ]]; then
        echo "$entries" > "$outfile"
        echo "✔︎ [$url] => OK"
        return
      fi
      echo "↪ [$url] => .entries vide"
    else
      echo "✘ [$url] => YAML invalide"
    fi
  else
    echo "✘ [$url] => Échec téléchargement (timeout ? erreur HTTP ?)"
  fi
}

while IFS= read -r url || [ -n "$url" ]; do
  [ -z "$url" ] && continue
  tmpfile="$TMPDIR/$(date +%s%N).yaml"
  process_url_bg "$url" "$tmpfile" &
  pids+=( $! )
  files+=( "$tmpfile" )
  # Attend si trop de jobs
  while (( $(jobs -rp | wc -l) >= NUM_JOBS )); do
    wait -n
  done
done < "$INPUT_FILE"

wait

entries_files=()
for f in "${files[@]}"; do
  if [ -s "$f" ]; then
    entries_files+=( "$f" )
  fi
done

if [ "${#entries_files[@]}" -eq 0 ]; then
  echo "apiVersion: v1" > "$MEGA_INDEX"
  echo "entries: {}" >> "$MEGA_INDEX" 
  echo "Aucun index valide trouvé, fichier vide créé : $MEGA_INDEX"
else
  BATCH=100
  intermediates=()
  total=${#entries_files[@]}
  for ((i=0; i<total; i+=BATCH)); do
    echo "Processing batch $i of $total"
    files=("${entries_files[@]:i:BATCH}")
    out="$TMPDIR/intermediate_$i.yaml"
    yq ea '. as $item ireduce ({}; . * $item )' "${files[@]}" > "$out"
    intermediates+=( "$out" )
  done
  echo "Fusion des fichiers intermédiaires"
  yq ea '. as $item ireduce ({}; . * $item )' "${intermediates[@]}" > "$TMPDIR/fused.yaml"
  echo "Fusion des fichiers intermédiaires => $TMPDIR/fused.yaml"
  echo "Enregistrement dans le Mega Index"
  echo "apiVersion: v1" > "$MEGA_INDEX"
  echo "entries:" >> "$MEGA_INDEX"
  yq ea '.entries = load("'$TMPDIR'/fused.yaml")' -n > "$MEGA_INDEX"
  echo "Enregistrement dans le Mega Index => $MEGA_INDEX"
  echo "Suppression des fichiers intermédiaires"
  rm -f "${intermediates[@]}"
  echo "Suppression des fichiers intermédiaires => OK"
fi