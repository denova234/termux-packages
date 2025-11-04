#!/bin/bash

# Simple script to build all Termux packages for aarch64

echo "Starting build process for all packages..."

# Check if we're in the right directory
if [ ! -d "packages" ]; then
    echo "Error: 'packages' directory not found!"
    exit 1
fi

if [ ! -f "build-package.sh" ]; then
    echo "Error: 'build-package.sh' not found!"
    exit 1
fi

# Loop through all package scripts
for package_script in packages/*.sh; do
    # Skip if no packages found
    if [ ! -f "$package_script" ]; then
        continue
    fi
    
    # Get just the package name without .sh extension
    package_name=$(basename "$package_script" .sh)
    
    echo "========================================"
    echo "Building: $package_name"
    echo "========================================"
    
    # Build the package - NO QUOTES around package_name
    ./build-package.sh -a aarch64 $package_name
    
    # Check if build was successful
    if [ $? -eq 0 ]; then
        echo "✓ Success: $package_name"
    else
        echo "✗ Failed: $package_name"
    fi
done

echo "Build process completed!"
