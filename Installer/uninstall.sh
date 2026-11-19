#!/bin/zsh
# Removes InputBattery completely (incl. settings and the widget's data file)
pkill -x InputBattery 2>/dev/null
sudo rm -rf /Applications/InputBattery.app
sudo pkgutil --forget de.mbmf17.inputbattery.pkg 2>/dev/null
defaults delete de.mbmf17.inputbattery 2>/dev/null
rm -rf "$HOME/Library/Application Support/InputBattery"
echo "InputBattery has been removed."
