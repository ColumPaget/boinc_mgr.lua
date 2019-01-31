SYNOPSIS
=========

boinc_mgr.lua is a menu-driven text-mode lua program for managing the boinc client app. It requires libUseful (at least version 4.0) and libUseful-lua (at least version 2.0) to be installed. boinc_mgr.lua can start and stop the boinc client app on local host, can join, attach, and detach from projects, and can start/stop tasks. It can also attach to boinc over tcp, and over tcp-over-ssh.

USAGE
=====
```
boinc_mgr.lua [host] [-key gui-key] [-user username] [-email email-address] [-pass password] [-save]

host  -  host to connect to. e.g. "tcp:192.168.2.1" or "ssh:myserver"

-key [gui-key]    This supplies the gui-key for a boinc process. This is needed for most control operations.
                  This key is normally found in the file "gui_rpc_auth.cfg" in whatever directory the boinc
                  process is running in.
 
-save             save the gui-key.


-user             Username. Needed for creating/joining project accounts and other management tasks.
-email            email address. Needed for creating/joining project accounts
-pass             password. Needed for creating/joining project accounts and other management tasks.

```

The user, email, pass and gui-key can be set within the program itself, so that they don't need to be passed on the command-line every time. The gui-key can be saved on a per-host basis by using the "-save" option. This will save the key for the current host in "~/.boinc/keys.txt", allowing multiple hosts to be accessed without needing to pass in the key.

Hosts that are accessed via SSH must be configured in the ~/.ssh/config file with an ssh key.

If run without any arguments the program will try to connect to a boinc process at "tcp:localhost". If it can't connect it will offer to start a new boinc process in "~/.boinc" and store the key for it.

Currently the "Settings" menu just displays the app settings, they cannot yet be modified. However, projects and tasks can be managed via the menus.
