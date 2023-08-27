cd BetterTG/Secret
find . -name "*.gyb" |
while read file; do
    filename=$(echo "$file" | sed 's/.\///')
    API_ID=$1 API_HASH=$2 gyb --line-directive '' -o "${filename%.gyb}" "$filename";
done

cd ../..
