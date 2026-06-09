function blur
    set config ~/.config/ghostty/config
    if grep -q "background-blur = true" $config
        sed -i 's/background-blur = true/background-blur = false/' $config
        echo "Ghostty blur: OFF"
    else
        sed -i 's/background-blur = false/background-blur = true/' $config
        echo "Ghostty blur: ON"
    end
    echo "Reload with Ctrl+Shift+,"
end
