#!/bin/bash

BASE_URL="https://artifacthub.io/api/v1/repositories/search"
LIMIT=60
offset=0
declare -A urls  # tableau associatif pour éviter les doublons

# Récupérer les headers + le body séparément pour lire le total
response=$(curl -sD - -o tmp_body.txt -G "$BASE_URL" \
  --data-urlencode "offset=0" \
  --data-urlencode "limit=$LIMIT" \
  --data-urlencode "kind=0" \
  -H "accept: application/json")

# Lire la valeur exacte du header pagination-total-count, insensible à la casse
total=$(echo "$response" | grep -i "pagination-total-count:" | awk '{print $2}' | tr -d '\r')

if [[ -z "$total" ]]; then
  echo "Erreur : impossible de récupérer le total dans les headers. Tentative en mode boucle infinie."
  total=9999999
fi

while [[ $offset -lt $total ]]; do
  echo "Fetching offset $offset ..."
  # Utilise -D - pour inclure les headers dans la sortie si besoin
  page=$(curl -sG "$BASE_URL" \
    --data-urlencode "offset=$offset" \
    --data-urlencode "limit=$LIMIT" \
    --data-urlencode "kind=0" \
    -H "accept: application/json")
    
  # Extraire les URLs uniquement des publishers vérifiés
  mapfile -t extracted_urls < <(echo "$page" | jq -r '.[] | select(.verified_publisher == true) | .url' | grep -v '^null$')
  for url in "${extracted_urls[@]}"; do
    urls["$url"]=1
  done
  offset=$((offset + LIMIT))
  sleep 0.1
done

# Afficher tous les URLs uniques récupérés
echo "Found ${#urls[@]} unique repository URLs:"
#for url in "${!urls[@]}"; do
  #echo "$url"
#done

# Nettoyage du fichier temporaire
rm -f tmp_body.txt
rm -f urls.txt

# Récupérer les données de chaque repository (uniquement qui commencent par http et ajouter index.yaml a la fin avec ou sans / selon le cas)
for url in "${!urls[@]}"; do
  if [[ $url == http* ]]; then
    if [[ $url == */ ]]; then
      echo "${url}index.yaml" >> urls.txt
    else
      echo "${url}/index.yaml" >> urls.txt
    fi
    #echo "$url"
  fi
done