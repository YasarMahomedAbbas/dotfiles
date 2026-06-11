function solid --description "Toggle Ghostty between translucent+blurred and fully solid"
    set config ~/.config/ghostty/config
    # "Normal" look to restore to when leaving solid mode. Change here if you
    # tweak your everyday opacity in the ghostty config.
    set normal_opacity 0.75

    if grep -q "^background-opacity = 1" $config
        # Currently solid -> back to normal translucent + blur
        sed -i "s/^background-opacity = .*/background-opacity = $normal_opacity/" $config
        sed -i 's/^background-blur = .*/background-blur = true/' $config
        echo "Ghostty: translucent + blur ON"
    else
        # Go fully solid
        sed -i 's/^background-opacity = .*/background-opacity = 1/' $config
        sed -i 's/^background-blur = .*/background-blur = false/' $config
        echo "Ghostty: fully SOLID"
    end
    echo "Reload blur with Ctrl+Shift+,  —  opacity change may need a new window/restart on GTK"
end
