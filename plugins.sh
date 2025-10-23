#!/bin/bash

install_plugin() {
    echo "Installing $plugin...."
    sudo -u $user $OCTOPIP install "$plugin_path"
}

plugin_menu() {
    echo
    echo
    get_settings
    PS3="${green}Select recommended plugins to install: ${white}"
    readarray -t plugins < <(cat $SCRIPTDIR/plugins_list | sed -n -e 's/^plugin:\(.*\) path:.*/\1/p')
    plugins+=("All")
    plugins+=("Quit")
    select plugin in "${plugins[@]}"
    do
        if [ "$plugin" == Quit ]; then
            break
            
        fi
        
        #some special thing to do if All Recommended
        if [ "$plugin" == All ]; then
            for plugin in "${plugins[@]}"; do
                plugin_path=$(cat $SCRIPTDIR/plugins_list | sed -n -e "s/^plugin:$plugin path:\([[:graph:]]*\)/\1/p")
                if [ -n "$plugin_path" ]; then
                    install_plugin $plugin $plugin_path
                fi
            done
            break
            sudo systemctl restart $INSTANCE
        fi
        #install single plugin
        #get plugin path
        plugin_path=$(cat $SCRIPTDIR/plugins_list | sed -n -e "s/^plugin:$plugin path:\([[:graph:]]*\)/\1/p")
        install_plugin 
    done
    
}

