mkdir Shared/Utilities/Generated
cd Shared/Utilities/Templates
find . -name "*.gyb" |
while read file; do
    filename=$(echo "$file" | sed 's/.\///')
    API_ID=$1 API_HASH=$2 gyb --line-directive '' -o "../Generated/${filename%.gyb}" "$filename";
done

cd ../..
