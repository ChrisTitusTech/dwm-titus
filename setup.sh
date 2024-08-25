#!/bin/bash

# Check for sudo or doas
if command -v sudo > /dev/null 2>&1; then
    SUDO="sudo"
elif command -v doas > /dev/null 2>&1; then
    SUDO="doas"
else
    echo "Neither sudo nor doas found. Please install one of them and try again."
    exit 1
fi

# Check for root privileges
if ! $SUDO -v; then
    echo "This script requires sudo or doas privileges. Please run with appropriate permissions."
    exit 1
fi

# Function to handle errors
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to install dependencies for Debian-based distributions
install_debian() {
    $SUDO apt update || handle_error "Failed to update package lists"

    # Check if Xorg is installed
    if ! dpkg -s xserver-xorg x11-xserver-utils xinit >/dev/null 2>&1; then
        echo "Xorg not found. Installing Xorg and related packages..."
        $SUDO apt install -y xserver-xorg x11-xserver-utils xinit || handle_error "Failed to install Xorg and related packages"
    else
        echo "Xorg and related packages are already installed."
    fi

    $SUDO apt install -y libconfig-dev libdbus-1-dev libegl-dev libev-dev libgl-dev libepoxy-dev libpcre2-dev libpixman-1-dev libx11-xcb-dev libxcb1-dev libxcb-composite0-dev libxcb-damage0-dev libxcb-dpms0-dev libxcb-glx0-dev libxcb-image0-dev libxcb-present-dev libxcb-randr0-dev libxcb-render0-dev libxcb-render-util0-dev libxcb-shape0-dev libxcb-util-dev libxcb-xfixes0-dev libxext-dev meson ninja-build uthash-dev cmake libxft-dev libimlib2-dev libxinerama-dev libxcb-res0-dev alsa-utils i3-wm xfce4-power-manager || handle_error "Failed to install dependencies"
}

# Function to install dependencies for Red Hat-based distributions
install_redhat() {
    $SUDO yum groupinstall -y "Development Tools" || handle_error "Failed to install Development Tools"

    # Check if Xorg is installed
    if ! rpm -q xorg-x11-server-Xorg xorg-x11-server-utils xorg-x11-xinit >/dev/null 2>&1; then
        echo "Xorg not found. Installing Xorg and related packages..."
        $SUDO yum install -y xorg-x11-server-Xorg xorg-x11-server-utils xorg-x11-xinit || handle_error "Failed to install Xorg and related packages"
    else
        echo "Xorg and related packages are already installed."
    fi

    $SUDO yum install -y dbus-devel gcc git libconfig-devel libdrm-devel libev-devel libX11-devel libX11-xcb libXext-devel libxcb-devel libGL-devel libEGL-devel libepoxy-devel meson ninja-build pcre2-devel pixman-devel uthash-devel xcb-util-image-devel xcb-util-renderutil-devel xorg-x11-proto-devel xcb-util-devel cmake libxft-devel libimlib2-devel libxinerama-devel alsa-utils i3 xfce4-power-manager || handle_error "Failed to install dependencies"
}

# Function to install dependencies for Arch-based distributions
install_arch() {
    $SUDO pacman -Syu --noconfirm || handle_error "Failed to update system"

    # Check if Xorg is installed
    if ! pacman -Qi xorg-server xorg-xsetroot xorg-xinit >/dev/null 2>&1; then
        echo "Xorg not found. Installing Xorg and related packages..."
        $SUDO pacman -S --noconfirm xorg-server xorg-xsetroot xorg-xinit || handle_error "Failed to install Xorg and related packages"
    else
        echo "Xorg and related packages are already installed."
    fi

    $SUDO pacman -S --noconfirm base-devel libconfig dbus libev libx11 libxcb libxext libgl libegl libepoxy meson pcre2 pixman uthash xcb-util-image xcb-util-renderutil xorgproto cmake libxft libimlib2 libxinerama libxcb-res xorg-xev alsa-utils pulseaudio-alsa i3-wm xfce4-power-manager || handle_error "Failed to install dependencies"

    # AUR helper installation
    if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
        echo "No AUR helper found. Installing yay..."
        git clone https://aur.archlinux.org/yay.git || handle_error "Failed to clone yay repository"
        cd yay
        makepkg -si --noconfirm || handle_error "Failed to install yay"
        cd ..
        rm -rf yay
    fi

    # Install brillo using the available AUR helper
    if command -v yay &> /dev/null; then
        yay -S --noconfirm brillo || handle_error "Failed to install brillo"
    elif command -v paru &> /dev/null; then
        paru -S --noconfirm brillo || handle_error "Failed to install brillo"
    else
        echo "No AUR helper available. Skipping brillo installation."
    fi
}

# Detect the distribution and install the appropriate packages
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        debian|ubuntu)
            echo "Detected Debian-based distribution"
            echo "Installing Dependencies using apt"
            install_debian
            ;;
        rhel|centos|fedora)
            echo "Detected Red Hat-based distribution"
            echo "Installing dependencies using Yellowdog Updater Modified"
            install_redhat
            ;;
        arch)
            echo "Detected Arch-based distribution"
            echo "Installing packages using pacman"
            install_arch
            ;;
        *)
            handle_error "Unsupported distribution"
            ;;
    esac
else
    handle_error "OS ID cannot be found. Unsupported distribution"
fi

# Function to install Meslo Nerd font for dwm and rofi icons to work
install_nerd_font() {
    FONT_DIR="$HOME/.local/share/fonts"
    FONT_ZIP="$FONT_DIR/Meslo.zip"
    FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip"
    FONT_INSTALLED=$(fc-list | grep -i "Meslo")

    # Check if Meslo Nerd-font is already installed
    if [ -n "$FONT_INSTALLED" ]; then
        echo "Meslo Nerd-fonts are already installed."
        return 0
    fi

    echo "Installing Meslo Nerd-fonts"

    # Create the fonts directory if it doesn't exist
    if [ ! -d "$FONT_DIR" ]; then
        mkdir -p "$FONT_DIR" || {
            echo "Failed to create directory: $FONT_DIR"
            return 1
        }
    else
        echo "$FONT_DIR exists, skipping creation."
    fi

    # Check if the font zip file already exists
    if [ ! -f "$FONT_ZIP" ]; then
        # Download the font zip file
        wget -P "$FONT_DIR" "$FONT_URL" || {
            echo "Failed to download Meslo Nerd-fonts from $FONT_URL"
            return 1
        }
    else
        echo "Meslo.zip already exists in $FONT_DIR, skipping download."
    fi

    # Unzip the font file if it hasn't been unzipped yet
    if [ ! -d "$FONT_DIR/Meslo" ]; then
        unzip "$FONT_ZIP" -d "$FONT_DIR" || {
            echo "Failed to unzip $FONT_ZIP"
            return 1
        }
    else
        echo "Meslo font files already unzipped in $FONT_DIR, skipping unzip."
    fi

    # Remove the zip file
    rm "$FONT_ZIP" || {
        echo "Failed to remove $FONT_ZIP"
        return 1
    }

    # Rebuild the font cache
    fc-cache -fv || {
        echo "Failed to rebuild font cache"
        return 1
    }

    echo "Meslo Nerd-fonts installed successfully"
}

picom_animations() {
    # Clone the repository in the home/build directory
    mkdir -p ~/build
    if [ ! -d ~/build/picom ]; then
        if ! git clone https://github.com/FT-Labs/picom.git ~/build/picom; then
            echo "Failed to clone the repository"
            return 1
        fi
    else
        echo "Repository already exists, skipping clone"
    fi

    cd ~/build/picom || { echo "Failed to change directory to picom"; return 1; }

    # Build the project
    if ! meson setup --buildtype=release build; then
        echo "Meson setup failed"
        return 1
    fi

    if ! ninja -C build; then
        echo "Ninja build failed"
        return 1
    fi

    # Install the built binary
    if ! $SUDO ninja -C build install; then
        echo "Failed to install the built binary"
        return 1
    fi

    echo "Picom animations installed successfully"
}

clone_config_folders() {
    # Ensure the target directory exists
    [ ! -d ~/.config ] && mkdir -p ~/.config

    # Iterate over all directories in config/*
    for dir in config/*/; do
        # Extract the directory name
        dir_name=$(basename "$dir")

        # Clone the directory to ~/.config/
        if [ -d "$dir" ]; then
            cp -r "$dir" ~/.config/
            echo "Cloned $dir_name to ~/.config/"
        else
            echo "Directory $dir_name does not exist, skipping"
        fi
    done
}

configure_backgrounds() {
    # Set the variable BG_DIR to the path where backgrounds will be stored
    BG_DIR="~/Pictures/backgrounds"

    # Check if the ~/Pictures directory exists
    if [ ! -d "~/Pictures" ]; then
        # If it doesn't exist, print an error message and return with a status of 1 (indicating failure)
        echo "Pictures directory does not exist"
        mkdir ~/Pictures
        echo "Directory was created in Home folder"
    fi
    
    # Check if the backgrounds directory (BG_DIR) exists
    if [ ! -d "$BG_DIR" ]; then
        # If the backgrounds directory doesn't exist, attempt to clone a repository containing backgrounds
        if ! git clone https://github.com/ChrisTitusTech/nord-background.git ~/Pictures; then
            # If the git clone command fails, print an error message and return with a status of 1
            echo "Failed to clone the repository"
            return 1
        fi
        # Rename the cloned directory to 'backgrounds'
        mv ~/Pictures/nord-background ~/Pictures/backgrounds
        # Print a success message indicating that the backgrounds have been downloaded
        echo "Downloaded desktop backgrounds to $BG_DIR"    
    else
        # If the backgrounds directory already exists, print a message indicating that the download is being skipped
        echo "Path $BG_DIR exists for desktop backgrounds, skipping download of backgrounds"
    fi
}

# Call the function
install_nerd_font

# Call the function
clone_config_folders

# Call the function
picom_animations

# Call the function
configure_backgrounds

echo "All dependencies installed successfully."