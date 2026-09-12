#!/bin/bash -e

# List of scripts supported by Google Noto packages in Fedora
indic_langs=(
devanagari
tamil
telugu
malayalam
kannada
oriya
bengali
gujarati
gurmukhi
)

# Initialize an empty array for packages
packages=()

for lang in "${indic_langs[@]}"; do
    # Generate both sans and serif package names
    packages+=("google-noto-sans-${lang}-fonts")
    packages+=("google-noto-serif-${lang}-fonts")
done

echo "Installing: ${packages[*]}"

# Run the installation
sudo dnf install "${packages[@]}"
