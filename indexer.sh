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
  BATCH=200
  total=${#entries_files[@]}
  batch_num=0
  
  for ((i=0; i<total; i+=BATCH)); do
    echo "Processing batch $i of $total"
    files=("${entries_files[@]:i:BATCH}")
    
    # Créer le répertoire pour ce batch si nécessaire
    batch_dir="tpl/$batch_num"
    mkdir -p "$batch_dir"
    
    # Créer l'index pour ce batch
    batch_index="$batch_dir/index.yaml"
    echo "apiVersion: v1" > "$batch_index"
    #echo "entries:" >> "$batch_index"
    
    # Fusionner les fichiers de ce batch
    yq ea '. as $item ireduce ({}; . * $item )' "${files[@]}" > "$TMPDIR/batch_$batch_num.yaml"
    yq ea '.entries = load("'$TMPDIR'/batch_'$batch_num'.yaml")' -n >> "$batch_index"
    
    rm -f "$TMPDIR/batch_$batch_num.yaml"
    echo "Batch $batch_num créé => $batch_index"
    
    ((batch_num++))
  done
  
  echo "Création des index par batch terminée"
  
  # Créer l'index principal qui référence tous les batch
  echo "apiVersion: v1" > "$MEGA_INDEX"
  echo "entries:" >> "$MEGA_INDEX"
  yq ea '. as $item ireduce ({}; . * $item )' tpl/*/index.yaml >> "$MEGA_INDEX"
  echo "Index principal créé => $MEGA_INDEX"
fi