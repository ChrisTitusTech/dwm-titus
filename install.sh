#!/usr/bin/env bash


RUNDIR=$PWD
echo "Installing dependencies..."

./setup_depends.sh

echo "Installing dwmblocks..."
if [ -d "$RUNDIR/dwmblocks/config.h" ]; then
    echo "dwmblocks is installed"
else
    echo "dwmblocks is not installed"
    echo "Installing dwmblocks..."
    cd "$RUNDIR" || exit
    sudo cp cpuu /bin/
    sudo chmod +x /bin/cpuu
    git submodule init dwmblocks
    git submodule update dwmblocks
    cd dwmblocks || exit
    make
    sudo make install
fi

cd "$RUNDIR" || exit


read -p "Do you want copy the config files (y/n): " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "Copying config files..."
    cp -r dotconfig/* ~/.config
fi

echo "Copying wallpaper"
cp chicken.jpg ~

echo "Installing sddm"
sudo systemctl enable sddm

make
sudo make install