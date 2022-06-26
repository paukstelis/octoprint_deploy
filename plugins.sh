#!/bin/bash

install_plugin() {
    echo "Installing $plugin...." | log
    $OCTOPIP install "$plugin_path"
}

plugin_menu() {
    
    PS3='Select recommended plugins to install: '
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
        fi
        #install single plugin
        #get plugin path
        plugin_path=$(cat $SCRIPTDIR/plugins_list | sed -n -e "s/^plugin:$plugin path:\([[:graph:]]*\)/\1/p")
        install_plugin 

        plugin_menu #keep going until quit
    done
    
}

plugin_menu_cloud() {
    echo
    echo "You can setup cloud-based plugins at this time. Some will have to be configured"
    echo "in your template instance before making new instances."
    echo
    PS3='Select cloud-based plugins to install: '
    readarray -t plugins < <(cat $SCRIPTDIR/plugins_cloud | sed -n -e 's/^plugin:\(.*\) path:.*/\1/p')
    plugins+=("Quit")
    select plugin in "${plugins[@]}"
    do
        if [ "$plugin" == Quit ]; then
            break
        fi
        plugin_path=$(cat $SCRIPTDIR/plugins_cloud | sed -n -e "s/^plugin:$plugin path:\([[:graph:]]*\)/\1/p")
        install_plugin 
        plugin_menu_cloud #keep going until quit
    done
}
